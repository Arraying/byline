{-# LANGUAGE OverloadedStrings #-}

{-

This file is part of the package byline. It is subject to the license
terms in the LICENSE file found in the top-level directory of this
distribution and at git://pmade.com/byline/LICENSE. No part of the
byline package, including this file, may be copied, modified,
propagated, or distributed except according to the terms contained in
the LICENSE file.

-}

--------------------------------------------------------------------------------
module System.Console.Byline.Menu
       ( Menu
       , Choice (..)
       , Matcher
       , menu
       , banner
       , prefix
       , suffix
       , matcher
       , askWithMenu
       , askWithMenuRepeatedly
       ) where

--------------------------------------------------------------------------------
import Control.Applicative
import Control.Monad
import Control.Monad.IO.Class
import qualified Control.Monad.Reader as Reader
import Data.IORef
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Maybe
import Data.Monoid
import Data.Text (Text)
import qualified Data.Text as Text
import System.Console.Byline.Internal.Byline
import System.Console.Byline.Internal.Completion
import System.Console.Byline.Internal.Render
import System.Console.Byline.Internal.Stylized
import System.Console.Byline.Primary
import Text.Printf (printf)

--------------------------------------------------------------------------------
-- | Internal representation of a menu.
data Menu a = Menu
  { menuItems        :: [a]
  , menuBanner       :: Maybe Stylized
  , menuDisplay      :: a -> Stylized
  , menuItemPrefix   :: Int -> Stylized
  , menuItemSuffix   :: Stylized
  , menuBeforePrompt :: Maybe Stylized
  , menuMatcher      :: Matcher a
  }

--------------------------------------------------------------------------------
-- | A type representing the choice made by a user while working with
-- a menu.
data Choice a = Match a         -- ^ User picked a menu item.
              | Other Text      -- ^ User entered some text.
              deriving Show

--------------------------------------------------------------------------------
-- | A function that is given the input from a user while working in a
-- menu and should translate that into a 'Choice'.  The map contains
-- the menu item prefixes (numbers or letters) and the items
-- themselves.
type Matcher a = Menu a -> Map Text a -> Text -> Choice a

--------------------------------------------------------------------------------
-- | Default prefix generator.  Creates numbers aligned for two-digit
-- prefixes.
numbered :: Int -> Stylized
numbered = text . Text.pack . printf "%2d"

--------------------------------------------------------------------------------
-- | Helper function to produce a list of menu items matching the
-- given user input.
matchOnPrefix :: Menu a -> Text -> [a]
matchOnPrefix config input = filter prefixCheck (menuItems config)
  where
    asText i      = renderText Plain (menuDisplay config i)
    prefixCheck i = input `Text.isPrefixOf` asText i

--------------------------------------------------------------------------------
-- | Default 'Matcher' function.  Checks to see if the user has input
-- a unique prefix for a menu item (matches the item text) or selected
-- one of the generated item prefixes (such as those generated by the
-- internal @numbered@ function).
defaultMatcher :: Matcher a
defaultMatcher config prefixes input =
  case uniquePrefix <|> Map.lookup input prefixes of
    Nothing    -> Other input
    Just match -> Match match

  where
    -- uniquePrefix :: Maybe a
    uniquePrefix = let matches = matchOnPrefix config input
                   in if length matches == 1
                        then listToMaybe matches
                        else Nothing

--------------------------------------------------------------------------------
-- | Default completion function.  Matches all of the menu items.
defaultCompFunc :: Menu a -> CompletionFunc
defaultCompFunc config (left, _) = return ("", completions matches)
  where
    -- All matching menu items.
    matches = if Text.null left
                then menuItems config
                else matchOnPrefix config (Text.reverse left)

    -- Convert a menu item to a String.
    asText i = renderText Plain (menuDisplay config i)

    -- Convert menu items into Completion values.
    completions = map (\i -> Completion (asText i) (asText i) False)

--------------------------------------------------------------------------------
-- | Create a 'Menu' by giving a list of menu items and a function
-- that can convert those items into stylized text.
menu :: [a] -> (a -> Stylized) -> Menu a
menu items displayF =
  Menu { menuItems        = items
       , menuBanner       = Nothing
       , menuDisplay      = displayF
       , menuItemPrefix   = numbered
       , menuItemSuffix   = text ") "
       , menuBeforePrompt = Nothing
       , menuMatcher      = defaultMatcher
       }

--------------------------------------------------------------------------------
-- | Change the banner of a menu.  The banner is printed just before
-- the menu items are displayed.
banner :: Stylized -> Menu a -> Menu a
banner b m = m {menuBanner = Just b}

--------------------------------------------------------------------------------
-- | Change the prefix function.  The prefix function should generate
-- unique, stylized text that the user can use to select a menu item.
-- The default prefix function numbers the menu items starting with 1.
prefix :: (Int -> Stylized) -> Menu a -> Menu a
prefix f m = m {menuItemPrefix = f}

--------------------------------------------------------------------------------
-- | Change the menu item suffix.  It is displayed directly after the
-- menu item prefix and just before the menu item itself.
--
-- Default: @") "@
suffix :: Stylized -> Menu a -> Menu a
suffix s m = m {menuItemSuffix = s}

--------------------------------------------------------------------------------
-- | Change the 'Matcher' function.  The matcher function should
-- compare the user's input to the menu items and their assigned
-- prefix values and return a 'Choice'.
matcher :: Matcher a -> Menu a -> Menu a
matcher f m = m {menuMatcher = f}

--------------------------------------------------------------------------------
-- | Ask the user to choose an item from a menu.  The menu will only
-- be shown once and the user's choice will be returned in a 'Choice'
-- value which may be 'Empty' or 'Other'.
--
-- If you want to force the user to only choose from the displayed
-- menu items you should use 'askWithMenuRepeatedly' instead.
askWithMenu :: (MonadIO m)
            => Menu a           -- ^ The 'Menu' to display.
            -> Stylized         -- ^ The prompt.
            -> Byline m (Choice a)
askWithMenu m prompt = do
  currCompFunc <- Reader.asks compFunc >>= liftIO . readIORef


  -- Use the default completion function for menus, but not if another
  -- completion function is already active.
  withCompletionFunc (fromMaybe (defaultCompFunc m) currCompFunc) $ do
    prefixes <- displayMenu
    answer   <- ask prompt Nothing
    return (menuMatcher m m prefixes answer)

  where
    -- Print the entire menu.
    displayMenu = do
      case menuBanner m of
        Nothing -> return ()
        Just br -> sayLn (br <> "\n")

      cache <- foldM listItem Map.empty $ zip  [1..] (menuItems m)

      case menuBeforePrompt m of
        Nothing -> sayLn mempty -- Just for the newline.
        Just bp -> sayLn ("\n" <> bp)

      return cache

    -- Print a menu item and cache its prefix in a Map.
    listItem cache (index, item) = do
      let bullet   = menuItemPrefix m index
          rendered = renderText Plain bullet

      sayLn $ mconcat [ text "  "          -- Indent.
                      , bullet             -- Unique identifier.
                      , menuItemSuffix m   -- Spacer or marker.
                      , menuDisplay m item -- The item.
                      ]

      return (Map.insert (Text.strip rendered) item cache)

--------------------------------------------------------------------------------
-- | Like 'askWithMenu' except that arbitrary input is not allowed.
-- If the user doesn't correctly select a menu item then the menu will
-- be repeated and an error message will be displayed.
askWithMenuRepeatedly :: (MonadIO m)
           => Menu a            -- ^ The 'Menu' to display.
           -> Stylized          -- ^ The prompt.
           -> Stylized          -- ^ Error message.
           -> Byline m (Choice a)
askWithMenuRepeatedly m prompt errprompt = go m
  where
    go config = do
      answer <- askWithMenu config prompt

      case answer of
        Match _ -> return answer
        _       -> go (config {menuBeforePrompt = Just errprompt})
