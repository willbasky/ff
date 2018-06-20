{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module FF.Github
    ( runCmdGithub
    ) where

import           Data.Foldable (toList)
import           Data.List (genericLength)
import           Data.List.Extra (groupSort)
import qualified Data.Map.Strict as Map
import           Data.Semigroup ((<>))
import           Data.Time (Day, UTCTime (..))
import           GitHub (Error, Id, Issue (..), IssueState (..), Milestone (..),
                         Name, Owner, Repo, URL (..), issueCreatedAt,
                         issueHtmlUrl, issueId, issueMilestone, issueState,
                         issueTitle, untagId)
import           GitHub.Endpoints.Issues (issuesForRepo)
import           Numeric.Natural (Natural)

import           FF.Storage (DocId (..))
import           FF.Types (ModeMap, NoteId, NoteView (..), Sample (..),
                           Status (..), taskMode)

runCmdGithub
    :: Name Owner
    -> Name Repo
    -> Natural  -- ^ limit
    -> Day      -- ^ today
    -> IO (Either Error (ModeMap Sample))
runCmdGithub owner repo limit today =
    fmap (sampleMaps limit today) <$> issuesForRepo owner repo mempty

sampleMaps :: Foldable t => Natural -> Day -> t Issue -> ModeMap Sample
sampleMaps limit today issues = Map.fromList $ takeFromMany limit groups
  where
    nvs = map toNoteView (toList issues)
    groups = groupSort [(taskMode today nv, nv) | nv <- nvs]
    takeFromMany _   []                   = []
    takeFromMany lim ((mode, notes) : gs) =
        (mode, Sample (take (fromIntegral lim) notes) len)
        : takeFromMany (lim `natSub` len) gs
      where
        len = genericLength notes
        natSub a b
            | a <= b    = 0
            | otherwise = a - b

toNoteView :: Issue -> NoteView
toNoteView Issue{..} = NoteView
    { nid    = toNoteId issueId
    , status = toStatus issueState
    , text   = issueTitle <> maybeUrl
    , start  = utctDay issueCreatedAt
    , end    = maybeMilestone
    }
  where
    maybeUrl = case issueHtmlUrl of
        Just (URL url) -> "\nurl " <> url
        Nothing        -> ""
    maybeMilestone = case issueMilestone of
        Just Milestone{milestoneDueOn = Just UTCTime{utctDay}} -> Just utctDay
        _                                                      -> Nothing

toNoteId :: Id Issue -> NoteId
toNoteId = DocId . show . untagId

toStatus :: IssueState -> Status
toStatus = \case
    StateOpen   -> Active
    StateClosed -> Archived