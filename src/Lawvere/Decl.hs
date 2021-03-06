module Lawvere.Decl where

import Lawvere.Core
import Lawvere.Disp
import Lawvere.Expr
import Lawvere.Ob
import Lawvere.Parse
import Prettyprinter
import Protolude hiding (many, some)
import Text.Megaparsec

data SketchAr = SketchAr
  { name :: LcIdent,
    source :: Ob,
    target :: Ob
  }

instance Disp SketchAr where
  disp SketchAr {..} =
    disp name <+> ":" <+> disp source <+> "-->" <+> disp target

instance Parsed SketchAr where
  parsed = do
    name <- lexeme parsed
    _ <- symbol ":"
    source <- lexeme parsed
    _ <- symbol "-->"
    target <- parsed
    pure SketchAr {..}

data Sketch = Sketch
  { name :: UcIdent,
    overCat :: UcIdent,
    obs :: [UcIdent],
    ars :: [SketchAr]
  }

instance Disp Sketch where
  disp Sketch {..} =
    dispDef
      "sketch"
      (disp name <+> "over" <+> disp overCat)
      (braces (vsep ((("ob" <+>) . disp <$> obs) ++ (("ar" <+>) . disp <$> ars))))

instance Parsed Sketch where
  parsed = do
    kwSketch
    name <- lexeme parsed
    kwOver
    overCat <- lexeme parsed
    _ <- symbol "="
    (obs, ars) <- partitionEithers <$> pCommaSep '{' '}' (pOb <|> pAr)
    pure Sketch {..}
    where
      pOb = Left <$> (kwOb *> parsed)
      pAr = Right <$> (kwAr *> parsed)

data SketchInterp = SketchInterp
  { obs :: [(UcIdent, Expr)],
    ars :: [(LcIdent, Expr)]
  }
  deriving stock (Show, Generic)

instance Disp SketchInterp where
  disp SketchInterp {..} =
    braces . vsep . punctuate comma $
      (("ob" <+>) . dispMapping <$> obs)
        ++ (("ar" <+>) . dispMapping <$> ars)
    where
      dispMapping (x, e) = disp x <+> "|->" <+> disp e

instance Parsed SketchInterp where
  parsed = do
    mappings <- pCommaSep '{' '}' pMapping
    let (obs, ars) = partitionEithers mappings
    pure SketchInterp {..}
    where
      pMapping = (Left <$> (kwOb *> pMapsto)) <|> (Right <$> (kwAr *> pMapsto))
      pMapsto :: (Parsed a, Parsed b) => Parser (a, b)
      pMapsto = (,) <$> lexeme parsed <*> (symbol "|->" *> parsed)

data Decl
  = DAr Ob LcIdent Ob Ob Expr
  | DFreyd Ob LcIdent Ob Ob Expr
  | DOb Ob UcIdent Ob
  | DSketch Sketch
  | DInterp LcIdent UcIdent Expr SketchInterp Expr Expr

type Decls = [Decl]

pObDecl :: Parser Decl
pObDecl = do
  kwOb
  catName <- lexeme parsed
  name <- lexeme parsed
  lexChar '='
  ob <- parsed
  pure (DOb catName name ob)

pArDecl :: Parser () -> (Ob -> LcIdent -> Ob -> Ob -> Expr -> Decl) -> Parser Decl
pArDecl kw ctor = do
  kw
  catName <- lexeme parsed
  name <- lexeme parsed
  lexChar ':'
  a <- lexeme parsed
  _ <- symbol "-->"
  b <- lexeme parsed
  lexChar '='
  body <- parsed
  pure (ctor catName name a b body)

pInterpDecl :: Parser Decl
pInterpDecl = do
  kwInterp
  sketchName <- lexeme parsed
  interpName <- lexeme parsed
  lexChar '='
  kwOver
  overThis <- lexeme parsed
  kwHandling
  theInterp <- lexeme parsed
  kwSumming
  summing <- parsed
  kwSide
  side <- parsed
  pure (DInterp interpName sketchName overThis theInterp summing side)

instance Parsed Decl where
  parsed =
    choice
      [ pObDecl,
        pArDecl kwAr    DAr,
        pArDecl kwFreyd DFreyd,
        pInterpDecl,
        DSketch <$> parsed
      ]

instance Disp Decl where
  disp = \case
    DOb catName name ob -> dispDef "ob" (disp catName <+> disp name) (disp ob)
    DAr catName name a b body -> dispDef "ar" (disp catName <+> disp name <+> ":" <+> disp a <+> "-->" <+> disp b) (disp body)
    DSketch sketch -> disp sketch
    DInterp {} -> "TODO"
    DFreyd{} -> "TODO"

dispDef :: Text -> Doc Ann -> Doc Ann -> Doc Ann
dispDef defname thing body = nest 2 $ vsep [pretty defname <+> thing <+> "=", body]

instance Parsed Decls where
  parsed = sc *> some (lexeme parsed) <* sc

instance Disp Decls where
  disp ds = vsep ((<> line) . disp <$> ds)
