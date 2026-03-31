type
  Delimiter* = enum
    delimComma
    delimTab
    delimPipe

  KeyFoldingMode* = enum
    keyFoldOff
    keyFoldSafe

  PathExpansionMode* = enum
    pathExpandOff
    pathExpandSafe

  EncodeOptions* = object
    indent*: int
    delimiter*: Delimiter
    keyFolding*: KeyFoldingMode
    flattenDepth*: int

  DecodeOptions* = object
    indent*: int
    strict*: bool
    expandPaths*: PathExpansionMode

proc defaultEncodeOptions*(): EncodeOptions =
  EncodeOptions(
    indent: 2,
    delimiter: delimComma,
    keyFolding: keyFoldOff,
    flattenDepth: high(int),
  )

proc defaultDecodeOptions*(): DecodeOptions =
  DecodeOptions(
    indent: 2,
    strict: true,
    expandPaths: pathExpandOff,
  )

proc charOf*(delimiter: Delimiter): char =
  case delimiter
  of delimComma:
    ','
  of delimTab:
    '\t'
  of delimPipe:
    '|'

proc bracketSuffix*(delimiter: Delimiter): string =
  case delimiter
  of delimComma:
    ""
  of delimTab:
    "\t"
  of delimPipe:
    "|"
