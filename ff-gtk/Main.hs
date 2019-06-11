{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Main (main) where

import           Control.Lens (makeClassy_, (%~))
import           Control.Monad (void)
import           Control.Monad.Trans (lift)
import           Data.Function ((&))
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Vector as Vector
import qualified GI.Gtk as Gtk
import           GI.Gtk.Declarative (Attribute ((:=)), BoxChild (BoxChild), bin,
                                     container, defaultBoxChildProperties,
                                     expand, fill, on, widget)
import           GI.Gtk.Declarative.App.Simple (App (App), AppView,
                                                Transition (Exit, Transition),
                                                run)
import qualified GI.Gtk.Declarative.App.Simple
import           Pipes (Producer, each)
import           RON.Storage.FS (runStorage)
import qualified RON.Storage.FS as StorageFS

import           FF (getDataDir, loadTasks, noDataDirectoryMessage)
import           FF.Config (loadConfig)
import           FF.Types (Entity (Entity), Note (Note), NoteId,
                           NoteStatus (TaskStatus), Status (Active))
import qualified FF.Types

newtype State = State{tasks :: Map NoteId Note}
makeClassy_ ''State

data Event
    = Close
    | UpsertTask (Entity Note)

view :: State -> AppView Gtk.Window Event
view State{tasks} =
    bin Gtk.Window windowAttrs mainWidget
  where

    windowAttrs =
        [ #title := "ff-gtk"
        , #heightRequest := 300
        , #widthRequest  := 400
        , on #deleteEvent $ const (True, Close)
        ]

    mainWidget = container Gtk.Box
        [#orientation := Gtk.OrientationVertical]
        [taskList] -- , newTaskForm

    taskList =
        BoxChild defaultBoxChildProperties{expand = True, fill = True} $
        container Gtk.Box
            [#orientation := Gtk.OrientationVertical]
            (Vector.fromList
                [ taskWidget $ Entity noteId note
                | (noteId, note) <- Map.assocs tasks
                ])

    taskWidget :: Entity Note -> BoxChild Event
    taskWidget Entity{entityVal = Note{note_status, note_text}} =
        widget Gtk.Label
            [ #halign := Gtk.AlignStart
            , #label := (if isActive then id else strike) (Text.pack note_text)
            -- , #useMarkup := True
            , #wrap := True
            ]
      where
        isActive = note_status == TaskStatus Active
        strike text = "<s>" <> text <> "</s>"

    -- newTaskForm = widget Gtk.Entry
    --     [ #text := currentText
    --     , #placeholderText := "What needs to be done?"
    --     , onM #changed $ fmap NewTodoChanged . Gtk.entryGetText
    --     , on #activate NewTodoSubmitted
    --     ]

update :: State -> Event -> Transition State Event
update st = \case
    Close -> Exit
    UpsertTask Entity{entityId, entityVal} ->
        Transition (st & _tasks %~ Map.insert entityId entityVal) (pure Nothing)

main :: IO ()
main = do
    path <- getDataDirOrFail
    storage <- StorageFS.newHandle path

    void $
        run App { view
                , update
                , initialState = State{tasks = []}
                , inputs =
                    [ initiallyLoadActiveTasks storage
                    -- TODO , listenToChanges
                    ]
                }

initiallyLoadActiveTasks :: StorageFS.Handle -> Producer Event IO ()
initiallyLoadActiveTasks storage = do
    activeTasks <- lift $ runStorage storage $ loadTasks False
    each $ map UpsertTask activeTasks

getDataDirOrFail :: IO FilePath
getDataDirOrFail = do
    cfg     <- loadConfig
    dataDir <- getDataDir cfg
    case dataDir of
        Nothing -> fail noDataDirectoryMessage
        Just path -> pure path