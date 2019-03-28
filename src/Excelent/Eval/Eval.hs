module Excelent.Eval.Eval where

import qualified Data.Map as M
import qualified Data.Set as S
import Algebra.Graph.AdjacencyMap as G
import Data.Functor.Foldable
import Excelent.Definition
import Data.NumInstances.Tuple
import Control.Lens hiding (view)
import Control.Lens.Combinators hiding (view)

-- | The algebra expressing the evaluation of Expr structures into its results.
--   Expressions are dependent on the environment supplied and can on its own
--   also change the current environment in the form of 'caching' the
--   results of any cells calculated in the mean time.
evalAlg :: Algebra ExprF (Position -> Env -> (Env, ViewValue))
evalAlg (ConstIntF i)     _   env = (env, Right i)
evalAlg (PlusF exp1 exp2) pos env = (env2, do
        i <- vval1
        j <- vval2
        return $ i + j)
    where
        (env1, vval1) = exp1 pos env
        (env2, vval2) = exp2 pos env1
evalAlg (RefRelF p) pos env = doLookup (pos + p) env
evalAlg (RefAbsF p) pos env = doLookup p env

-- | Try and either lookup the value of the given position if it was ever
--   calculated, or calculate it and save any cells calculated along the way in
--   the environment
doLookup :: Position -> Env -> (Env, ViewValue)
doLookup pos env = case M.lookup pos (env^.formulas) of 
    Nothing -> (env, Left "err: Empty")
    Just e -> case M.lookup pos (env^.view) of
        Nothing -> let (newEnv, val) = cata evalAlg e pos env in
            (newEnv & view %~ M.insert pos val, val)
        Just e' -> (env, e')
        

-- | Evaluate the given expression using the current position and its environment.
--   This is done using a catamorphism, which is automatically derived using the
--   recursion-schemes library
evalExpr :: Expr -> Position -> Env -> (Env, ViewValue)
evalExpr = cata evalAlg

-- | Ensures that the cell at the given position is evaluated, or in other words,
--   that the view record in the environment contains a value for the cell at
--   the position
evalCell :: Position -> Env -> Env
evalCell pos env = case M.lookup pos (env ^. view) of
    Just v -> env
    Nothing -> case M.lookup pos (env ^. formulas) of
        Just expr -> env & view %~ M.insert pos (snd $ evalExpr expr pos env)
        Nothing -> env & view %~ M.insert pos (Left "")

-- | Evaluate all of the cells 'visible' to the viewport
eval :: Env -> Env
eval env = resultEnv
    where
        resultEnv = foldr evalCell env positions
        positions = concat $ inView $ env ^. port

-- | Generates all positions which are in view as a list of columns
inView :: ViewPort -> [[Position]]
inView vp =
    [[(vp ^. position . _1 + i, vp ^. position . _2 + j) |
        i <- [0..vp ^. size . _1]] |
        j <- [0..vp ^. size . _2]]

-- | Removes the values in the ViewData in the environment at the given positions,
--   so that they can be recalculated.
invalidateView :: [Position] -> Env -> Env
invalidateView ps env = env & view %~ (`M.withoutKeys` set)
    where
        set = S.fromList ps
