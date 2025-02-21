{-# LANGUAGE OverloadedStrings #-}

module System.Nix.NarInfo
  ( NarInfo(..), NarCompressionType(..), FileHash
  , mkNarInfoEndpFromStoreHash
  , mkNarInfoEndpFromStoreName
  , decodeThrow
  ) where

import Control.Monad.Fail
import Data.Functor ((<&>))
import Data.Text (Text)
import Data.Yaml
import Prelude hiding (fail)
import qualified Data.Char as C
import qualified Data.Text as T

import System.Nix.StoreNames

data NarInfo = NarInfo
  { _storeName   :: !StoreName
  -- TODO convert url type to `ByteString`?
  , _url         :: !Text  -- ^ nar file url compressed or uncompressed
  , _compression :: !NarCompressionType -- ^ compression type: bz2, xz, none
  , _fileHash    :: !FileHash  -- ^ sha256 of nar file compressed or not
  , _fileSize    :: !Int
  , _narHash     :: Text   -- ^ uncompressed nar file hash
  , _narSize     :: Int
  , _references  :: ![StoreName]  -- ^ store hashes this references (depends)
  , _deriver     :: Maybe Text
  , _sig         :: Text
  } deriving (Eq, Show)

type FileHash = Text
type UrlEndpoint = Text

-- | Types of compression supported for NAR archives.
data NarCompressionType = CompBz2 | CompXz | CompNone
  deriving (Eq, Show)

instance FromJSON NarInfo where
  parseJSON (Object o) = NarInfo
    <$> (parseStorePath =<< o .: "StorePath")
    <*> o .: "URL"
    <*> (parseNarComp   =<< o .: "Compression")
    <*> (parseFileHash  =<< o .: "FileHash")
    <*> o .: "FileSize"
    <*> o .: "NarHash"
    <*> o .: "NarSize"
    <*> (parseRefs      =<< o .:? "References") -- optional
    <*> o .:? "Deriver"
    <*> o .: "Sig"
    <&> clearSelfRefs
  parseJSON x =
    fail $ "NarInfo YAML parsing Error! \
           \Given ByteString does not begin with YAML map:\n" ++ show x

-- Filter out references to itself.
clearSelfRefs :: NarInfo -> NarInfo
clearSelfRefs n =
  n {_references = filter (/= _storeName n) $ _references n}

parseNarComp :: MonadFail m => Text -> m NarCompressionType
parseNarComp "xz"    = pure CompXz
parseNarComp "bzip2" = pure CompBz2
parseNarComp "none"  = pure CompNone
parseNarComp t = failWith "Unexpected `Compression` type read from Narinfo" t

parseFileHash :: MonadFail m => Text -> m FileHash
parseFileHash t = case T.split (== ':') t of
                    ["sha256", base32hash] -> pure base32hash
                    _ -> failWith "sha256 `FileHash` cannot be parsed" t

parseRefs :: MonadFail m => Maybe Text -> m [StoreName]
parseRefs Nothing = return []
parseRefs (Just t) = either (fail . errorStack) pure mRefHashes
  where
    mRefHashes = traverse parseStoreName (T.words t)
    errorStack deeper =
      "invalid reference in:\n" ++ T.unpack t ++ "\n" ++ deeper

parseStorePath :: MonadFail m => Text -> m StoreName
parseStorePath t = either (fail . errorStack) pure $ stripParseStoreName t
  where
    errorStack deeper =
      "invalid store path in:\n" ++ T.unpack t ++ "\n" ++ deeper

-- | Parsing error message generation.
failWith :: MonadFail m => String -> Text -> m a
failWith desc tSrc =
-- If not using `fail` then what? `empty` does not include a custom message.
  fail $ "NarInfo YAML parsing Error! " ++ sentence ++ ": " ++ T.unpack tSrc
  where
    sentence = case desc of
                 (char:rest) -> C.toUpper char : rest
                 _ -> ""

-- | Make `UrlEndpoint` for NarInfo from StoreHash (Reference).
mkNarInfoEndpFromStoreHash :: StoreHash -> UrlEndpoint
mkNarInfoEndpFromStoreHash = flip T.append ".narinfo"

-- | Make `UrlEndpoint` for NarInfo from StoreHash (Reference).
mkNarInfoEndpFromStoreName :: StoreName -> UrlEndpoint
mkNarInfoEndpFromStoreName = mkNarInfoEndpFromStoreHash . storeNameHash
