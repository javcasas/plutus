{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}

module DynamicBuiltins.Logging
    ( test_logging
    ) where

import           Language.PlutusCore
import           Language.PlutusCore.Constant
import           Language.PlutusCore.Constant.Dynamic
import           Language.PlutusCore.MkPlc

import           Language.PlutusCore.StdLib.Data.List as Plc
import           Language.PlutusCore.StdLib.Data.Unit

import           DynamicBuiltins.Common

import           Control.Monad.Except
import           Data.Either                          (isRight)
import           Test.Tasty
import           Test.Tasty.HUnit

dynamicIntToStringName :: DynamicBuiltinName
dynamicIntToStringName = DynamicBuiltinName "intToString"

dynamicIntToStringMeaning :: DynamicBuiltinNameMeaning
dynamicIntToStringMeaning = DynamicBuiltinNameMeaning sch show where
    sch =
        TypeSchemeAllSize $ \s ->
            TypeSchemeBuiltin (TypedBuiltinSized (SizeBound s) TypedBuiltinSizedInt) `TypeSchemeArrow`
            TypeSchemeBuiltin (TypedBuiltinDyn @String)

dynamicIntToString :: Term tyname name ()
dynamicIntToString = dynamicBuiltinNameAsTerm dynamicIntToStringName

handleDynamicIntToString :: OnChainHandler "intToString" f r r
handleDynamicIntToString = handleDynamicByMeaning dynamicIntToStringMeaning

evaluateHandlersCek
    :: MonadError (Error ()) m
    => (Evaluator (OnChain '[] Term) m -> OnChainEvaluator names Term r)
    -> OnChain names Term TyName Name ()
    -> r
evaluateHandlersCek = evaluateHandlersBy typecheckEvaluateCek

test_logInt :: TestTree
test_logInt = testCase "logInt" $ do
    let size = 4
        term
            = Apply () dynamicLog
            . Apply () (TyInst () dynamicIntToString (TyInt () size))
            $ Constant () (BuiltinInt () size 1)

    let eval1 = evaluateHandlersCek (handleDynamicIntToString . handleDynamicLog)
    let eval2 = evaluateHandlersCek (handleDynamicLog . handleDynamicIntToString)
    (logs1, errOrRes1) <- eval1 $ OnChain term
    (logs2, errOrRes2) <- eval2 $ OnChain term
    isRight errOrRes1 @?= True
    isRight errOrRes2 @?= True
    logs1 @?= ["1"]
    logs2 @?= ["1"]

test_logInts :: TestTree
test_logInts = testCase "logInts" $ do
    let term = runQuote $ do
            let size = 4
                int4 = TyApp () (TyBuiltin () TyInteger) (TyInt () size)
            u <- freshName () "u"
            x <- freshName () "x"

            return
                $ mkIterApp () (mkIterInst () foldList [int4, unit])
                    [   LamAbs () u unit
                      . LamAbs () x int4
                      . Apply () dynamicLog
                      . Apply () (TyInst () dynamicIntToString (TyInt () size))
                      $ Var () x
                    , unitval
                    , mkIterApp () (TyInst () Plc.enumFromTo (TyInt () size))
                        [ Constant () $ BuiltinInt () size 1
                        , Constant () $ BuiltinInt () size 10
                        ]
                    ]

    let eval1 = evaluateHandlersCek (handleDynamicIntToString . handleDynamicLog)
    let eval2 = evaluateHandlersCek (handleDynamicLog . handleDynamicIntToString)
    (logs1, errOrRes1) <- liftIO . eval1 $ OnChain term
    (logs2, errOrRes2) <- liftIO . eval2 $ OnChain term
    isRight errOrRes1 @?= True
    isRight errOrRes2 @?= True
    logs1 @?= map show [1 .. 10 :: Int]
    logs2 @?= map show [1 .. 10 :: Int]

test_logging :: TestTree
test_logging =
    testGroup "logging"
        [ test_logInt
        , test_logInts
        ]
