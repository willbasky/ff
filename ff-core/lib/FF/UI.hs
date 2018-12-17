{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeApplications #-}

module FF.UI (
    contactViewFull,
    noteViewFull,
    prettyContactSamplesOmitted,
    prettyNotes,
    prettyNotesWikiContacts,
    prettySamplesBySections,
    prettyWikiSamplesOmitted,
    sampleFmap,
    sampleLabel,
    withHeader,
) where

import           Data.Char (isSpace)
import           Data.List (genericLength, intersperse)
import qualified Data.Map.Strict as Map
import           Data.Semigroup ((<>))
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Lazy.Encoding as TextL
import           Data.Text.Prettyprint.Doc (Doc, Pretty (..), fillSep, hang,
                                            indent, sep, space, viaShow, vsep,
                                            (<+>))
import           Data.Time (Day)
import           RON.Text.Serialize (serializeUuid)
import           RON.Types (UUID)
import qualified RON.UUID as UUID

import           FF.Types (Contact (..), ContactSample, Entity (..), ModeMap,
                           Note (..), NoteSample, Sample (..), TaskMode (..),
                           Track (..), omitted)

(.=) :: Text -> Text -> Doc ann
label .= value = hang indentation $ fillSep [pretty label, pretty value]

withHeader :: Text -> Doc ann -> Doc ann
withHeader header value = hang indentation $ vsep [pretty header, value]

indentation :: Int
indentation = 2

prettyUuid :: UUID -> Doc ann
prettyUuid = pretty . TextL.decodeUtf8 . serializeUuid

prettyNotesWikiContacts
    :: Bool  -- ^ brief output
    -> ModeMap NoteSample
    -> NoteSample
    -> ContactSample
    -> Bool  -- ^ search among tasks
    -> Bool  -- ^ search among wiki notes
    -> Bool  -- ^ search among contacts
    -> Doc ann
prettyNotesWikiContacts brief notes wiki contacts amongN amongW amongC =
    case (amongN, amongW, amongC) of
        (True,  False, False) -> ns
        (False, True,  False) -> ws
        (False, False, True ) -> cs
        (True,  True,  False) -> vsep [ns, ws]
        (False, True,  True ) -> vsep [ws, cs]
        (True,  False, True ) -> vsep [ns, cs]
        (_,     _,     _    ) -> vsep [ns, ws, cs]
  where
    ns = prettySamplesBySections brief notes
    ws = prettyWikiSamplesOmitted brief wiki
    cs = prettyContactSamplesOmitted brief contacts

prettyContactSamplesOmitted :: Bool -> ContactSample -> Doc ann
prettyContactSamplesOmitted brief samples = stack' brief $
    prettyContactSample brief samples :
    [pretty numOmitted <> " task(s) omitted" | numOmitted > 0]
  where
    numOmitted = omitted samples

prettyContactSample :: Bool -> ContactSample -> Doc ann
prettyContactSample brief = \case
    Sample{sample_total = 0} -> "No contacts to show"
    Sample{sample_items} ->
        withHeader "Contacts:" . stack' brief $
        map ((star <>) . indent 1 . contactViewFull) sample_items

prettyWikiSamplesOmitted :: Bool -> NoteSample -> Doc ann
prettyWikiSamplesOmitted brief samples = stack' brief $
    prettyWikiSample brief samples :
    [pretty numOmitted <> " task(s) omitted" | numOmitted > 0]
  where
    numOmitted = omitted samples

prettyNotes :: Bool -> [Entity Note] -> Doc ann
prettyNotes brief = stack' brief . map ((star <>) . indent 1 . noteView brief)

prettyWikiSample :: Bool -> NoteSample -> Doc ann
prettyWikiSample brief = \case
    Sample{sample_total = 0} -> "No wikis to show"
    Sample{sample_items} ->
        withHeader "Wiki notes:" .
        stack' brief $
        map ((star <>) . indent 1 . noteView brief) sample_items

noteView :: Bool -> Entity Note -> Doc ann
noteView brief = if brief then noteViewBrief else noteViewFull

prettySamplesBySections :: Bool -> ModeMap (Sample (Entity Note)) -> Doc ann
prettySamplesBySections brief samples = stack' brief
    $   [prettySample brief mode sample | (mode, sample) <- Map.assocs samples]
    ++  [pretty numOmitted <> " task(s) omitted" | numOmitted > 0]
  where
    numOmitted = sum $ fmap omitted samples

prettySample :: Bool -> TaskMode -> Sample (Entity Note) -> Doc ann
prettySample brief mode = \case
    Sample{sample_total = 0} -> "No notes to show"
    Sample{sample_total, sample_items} ->
        withHeader (sampleLabel mode) . stack' brief $
            map ((star <>) . indent 1 . noteView brief) sample_items
            ++  [ toSeeAllLabel .= cmdToSeeAll mode
                | count /= sample_total
                ]
      where
        toSeeAllLabel = "To see all " <> Text.pack (show sample_total) <> " task(s), run:"
        count         = genericLength sample_items
  where
    cmdToSeeAll = \case
        Overdue _  -> "ff search --overdue"
        EndToday   -> "ff search --today"
        EndSoon _  -> "ff search --soon"
        Actual     -> "ff search --actual"
        Starting _ -> "ff search --starting"

sampleLabel :: TaskMode -> Text
sampleLabel = \case
    Overdue n -> case n of
        1 -> "1 day overdue:"
        _ -> Text.pack (show n) <> " days overdue:"
    EndToday -> "Due today:"
    EndSoon n -> case n of
        1 -> "Due tomorrow:"
        _ -> "Due in " <> Text.pack (show n) <> " days:"
    Actual -> "Actual:"
    Starting n -> case n of
        1 -> "Starting tomorrow:"
        _ -> "Starting in " <> Text.pack (show n) <> " days:"

noteViewBrief :: Entity Note -> Doc ann
noteViewBrief (Entity entityId Note{..}) = fillSep [title, meta]
  where
    meta = "| id" <+> prettyUuid entityId
    title
        = mconcat
        . map (fillSep . map pretty . Text.split isSpace)
        . take 1
        . Text.lines
        $ Text.pack note_text

noteViewFull :: Entity Note -> Doc ann
noteViewFull (Entity entityId Note{..}) =
    sparsedStack [wrapLines $ Text.pack note_text, sep meta]
  where
    meta
        = mconcat
            [ ["| id"    <+> prettyUuid entityId | entityId /= UUID.zero]
            , ["| start" <+> viaShow @Day note_start]
            , ["| end"   <+> viaShow @Day e | Just e <- [note_end]]
            ]
        ++  [ "| tracking" <+> pretty track_url
            | Just Track{..} <- [note_track]
            ]

contactViewFull :: Entity Contact -> Doc ann
contactViewFull (Entity entityId Contact{..}) =
    sep [pretty contact_name, meta]
  where
    meta = "| id" <+> prettyUuid entityId

wrapLines :: Text -> Doc ann
wrapLines =
    vsep . map (fillSep . map pretty . Text.split isSpace) . Text.splitOn "\n"

sparsedStack :: [Doc ann] -> Doc ann
sparsedStack = vsep . intersperse space

stack' :: Bool -> [Doc ann] -> Doc ann
stack' brief
    | brief     = vsep
    | otherwise = sparsedStack

sampleFmap :: (a -> b) -> Sample a -> Sample b
sampleFmap f sample@Sample{sample_items} =
    sample{sample_items = map f sample_items}

star :: Doc ann
star = "*"
