module Sheet where

import Data.Array
import Data.List
import Data.Maybe
import Data.Monoid ((<>))
import Data.NumInstances.Tuple
import Data.Text.Zipper
import qualified Data.Map as M
import qualified Text.Parsec as P

import Brick.AttrMap
import Brick.Focus
import Brick.Main
import Brick.Types
import Brick.Widgets.Core
import Brick.Widgets.Edit
import Brick.Widgets.Border
import Graphics.Vty


import Excelent.Definition
import Excelent.Eval.Eval
import Excelent.Parser
import Print
import Debug.Trace

data State = State {
        focus :: FocusRing Position,
        widgets :: Array Position (Editor String Position),
        env :: Env
    }

data Dir =  N | S | W | E

divideIntoGroupsOf :: Int -> [a] -> [[a]]
divideIntoGroupsOf n [] = [[]]
divideIntoGroupsOf n xs =
    let (xs1, xs2) = splitAt n xs in xs1 : divideIntoGroupsOf n xs2

main :: IO State
main = defaultMain app initialState

initialState :: State
initialState = State {
        focus = focusRing $ indices editors',
        widgets = editors',
        env = initial viewport
    }
    where
        editors' = editors viewport
        viewport = ViewPort {
            size = (10, 6),
            position = (0, 0)
        }

editors :: ViewPort -> Array Position (Editor String Position)
editors vp = array ((0, 0), (rows, cols))
    [ ((i, j), editor (i, j) (Just 1) "")
    | i <- [0..rows], j <- [0..cols]
    ]
    where
        (rows, cols) = size vp - (1, 1)

app :: App State e Position
app = App
    { appDraw = draw
    , appChooseCursor = focusRingCursor focus
    , appHandleEvent = handleEvent
    , appStartEvent = return
    , appAttrMap = const $ attrMap defAttr []
    }

draw :: State -> [Widget Position]
draw state'
    = [vBox $ hBox <$> divideIntoGroupsOf cols ws]
  where
    (rows, cols) = size p
    r = focus state'
    eds = widgets state'
    ws = map border $ elems $ withFocusRing r (renderEditor $ str . head) <$> eds
    Env{formulas = f, view = v, port = p} = env state'

show' :: State -> Dir -> Array Position (Editor String Position)
show' state@State {widgets = w, env = e} d
    = w //
        [((i,j),
            if not (inFocus pos d (i,j))
                then applyEdit ((\w -> foldl' (flip insertChar) w (printV (i, j) v)) . clearZipper) (ed i j)
                else applyEdit ((\w -> foldl' (flip insertChar) w (printF (i, j) f)) . clearZipper) (ed i j))
        | i <- [0..fst (size p) - 1], j <- [0..snd (size p) - 1]
        ]
    where
    Env{formulas = f, view = v, port = p} = e
    ed i j = widgets state ! (i,j)
    pos = currentPosition state

inFocus :: Position -> Dir -> Position -> Bool
inFocus current dir check = current + move dir == check

currentPosition :: State -> Position
currentPosition state = fromJust $ focusGetCurrent (focus state)

move :: Dir -> (Int, Int)
move W = ( 0,-1)
move E = ( 0, 1)
move N = (-1, 0)
move S = ( 1, 0)

--Insert result of eval, except for the one in focus.
updateEditors :: State -> Dir -> State
updateEditors state dir = state' {focus = ring (move dir), widgets = show' state' dir}
  where
    ring d = focusSetCurrent (pos + d) (focus state')
    insertedText = getEditContents (widgets state ! pos)
    parsed = P.parse expression "" (concat insertedText)
    oldEnv = case parsed of
        Left err -> env state
        Right expr -> (env state) { view = M.empty, formulas = M.insert pos expr (formulas $ env state)}
    newEnv = eval oldEnv
    state' = state {env = newEnv}
    form' = formulas $ env state'
    view' = view $ env state'
    pos = currentPosition state

{-
Array Position (Editor String Position)
updateEditors (r,eds) = eds // [((i,j), if not (inFocus (i, j)) then applyEdit (insertChar 'a' . clearZipper) (ed i j) else ed i j)
                               | i <- [1..numberOfRows], j <- [1..numberOfColumns]
                               ]
    where ed i j = eds ! (i,j)
          inFocus e = fromJust (focusGetCurrent r) == e
-}
handleEvent :: State -> BrickEvent Position e -> EventM Position (Next State)
handleEvent state' (VtyEvent e) = case e of
    EvKey KLeft  [] -> continue $ updateEditors state' W
    EvKey KRight [] -> continue $ updateEditors state' E
    EvKey KUp    [] -> continue $ updateEditors state' N
    EvKey KDown  [] -> continue $ updateEditors state' S
    EvKey KEnter [] -> continue $ updateEditors state' S
    EvKey KEsc   [] -> halt state'
    _               -> do
        ed' <- handleEditorEvent e ed
        continue state' {widgets = widgets state' // [(pos, ed')]}
  where
    ed = widgets state' ! pos
    pos = currentPosition state'
handleEvent state' _ = continue state'
