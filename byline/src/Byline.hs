-- |
--
-- Copyright:
--   This file is part of the package addy. It is subject to the license
--   terms in the LICENSE file found in the top-level directory of this
--   distribution and at:
--
--     https://github.com/pjones/byline
--
--   No part of this package, including this file, may be copied,
--   modified, propagated, or distributed except according to the terms
--   contained in the LICENSE file.
--
-- License: BSD-2-Clause
module Byline
  ( -- * How to use this library
    -- $use

    -- * Byline class and transformer
    MonadByline,
    BylineT,
    runBylineT,

    -- * Basic user interaction
    say,
    sayLn,
    askLn,
    askChar,
    askPassword,
    askUntil,

    -- * Stylizing modifiers
    Stylized,
    ToStylizedText (..),
    text,
    fg,
    bg,
    bold,
    underline,
    swapFgBg,

    -- * Colors
    Color,
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    rgb,

    -- * Completion
    CompletionFunc,
    Completion (..),
    pushCompletionFunction,
    popCompletionFunction,
  )
where

import Byline.Internal.Color
import Byline.Internal.Completion
import Byline.Internal.Eval (BylineT, MonadByline (..), runBylineT)
import qualified Byline.Internal.Prim as Prim
import Byline.Internal.Stylized
import Prelude hiding (ask)

-- | Output the given stylized text.
--
-- See also: 'sayLn'.
--
-- @since 1.0.0.0
say ::
  (MonadByline m, ToStylizedText a) =>
  -- | The stylized text to output.
  a ->
  m ()
say =
  toStylizedText
    >>> Prim.say
    >>> liftByline

-- | Like 'say', but append a newline character.
--
-- @since 1.0.0.0
sayLn ::
  (MonadByline m, ToStylizedText a) =>
  -- | The stylized text to output.  An appropirate line ending
  -- character will be added to the end of this text.
  a ->
  m ()
sayLn =
  toStylizedText
    >>> Prim.sayLn
    >>> liftByline

-- | Read a line of input after printing the given stylized text as a
-- prompt.
--
-- @since 1.0.0.0
askLn ::
  (MonadByline m, ToStylizedText a) =>
  -- | The prompt.
  a ->
  -- | The text to return if the user does not enter a response.
  Maybe Text ->
  -- | User input (or default answer).
  m Text
askLn prompt def = liftByline (Prim.askLn (toStylizedText prompt) def)

-- | Read a single character of input.
--
-- @since 1.0.0.0
askChar ::
  (MonadByline m, ToStylizedText a) =>
  -- | The prompt to display.
  a ->
  m Char
askChar =
  toStylizedText
    >>> Prim.askChar
    >>> liftByline

-- | Read a password without echoing it to the terminal.  If a masking
-- character is given it will replace each typed character.
--
-- @since 1.0.0.0
askPassword ::
  (MonadByline m, ToStylizedText a) =>
  -- | The prompt to display.
  a ->
  -- | Optional masking character that will be printed each time the
  -- user presses a key.  When 'Nothing' is given the default behavior
  -- will be used which is system dependent but usually results in no
  -- characters being echoed to the terminal.
  Maybe Char ->
  m Text
askPassword prompt =
  Prim.askPassword (toStylizedText prompt)
    >>> liftByline

-- | Continue to prompt for a response until a confirmation function
-- returns a valid result.
--
-- @since 1.0.0.0
askUntil ::
  (MonadByline m, ToStylizedText a, ToStylizedText e) =>
  -- | The prompt to display.
  a ->
  -- | The default answer if the user presses enter without typing
  -- anything.
  Maybe Text ->
  -- | A function to validate the user input.  If the user input is
  -- acceptable the function should return 'Right'.  If the input is
  -- invalid then it should return 'Left' with an error message to
  -- display.  The error message will be printed with 'sayLn'.
  (Text -> m (Either e b)) ->
  m b
askUntil prompt def confirm = go
  where
    go = do
      answer <- askLn prompt def
      confirm answer >>= \case
        Left msg -> sayLn msg >> go
        Right res -> pure res

-- | Add a 'CompletionFunc' to the stack.
--
-- @since 1.0.0.0
pushCompletionFunction :: MonadByline m => CompletionFunc IO -> m ()
pushCompletionFunction = Prim.pushCompFunc >>> liftByline

-- | Remove the top completion function from the stack.
--
-- @since 1.0.0.0
popCompletionFunction :: MonadByline m => m ()
popCompletionFunction = liftByline Prim.popCompFunc

-- $use
--
--  Byline provides a monad transformer that allows you to compose
-- interactive terminal actions.  When producing output,
-- these actions accept stylized text that can include
-- foreground and background colors, underlined text, and
-- bold text.
--
-- Stylized text can be constructed with string literals
-- (using the @OverloadedStrings@ extension) or using the
-- 'text' function.  Attributes such as color can be changed
-- using modifier functions and the 'Semigroup' @(<>)@ operator.
--
-- Actions that read user input can work with completion
-- functions which are activated when the user presses the
-- tab key.  Most input actions also support default values
-- that will be returned when the user presses the enter key
-- without providing any input.
--
-- Example:
--
-- @
-- {-\# LANGUAGE OverloadedStrings \#-}
--
--
-- main = do
--   language <- 'runBylineT' $ do
--     'sayLn' ("Look mom, " <> ("colors" <> 'fg' 'blue') <> "!")
--
--     let question = "What's your favorite " <>
--                    ("language" <> 'bold') <> "? "
--
--     'askLn' question Nothing
--  print language
-- @
--
-- More complete examples can be found in the @examples@
-- directory of the distribution tarball or in the
-- repository.
