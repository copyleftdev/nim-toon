import std/options

import ./options

type
  LineInfo* = object
    number*: int
    raw*: string
    content*: string
    depth*: int
    indentSpaces*: int
    isBlank*: bool

  HeaderSpec* = object
    key*: string
    hasKey*: bool
    count*: int
    delimiter*: Delimiter
    fields*: seq[string]
    inline*: string

  ParserState* = object
    lines*: seq[LineInfo]
    index*: int
    options*: DecodeOptions

  HeaderResult* = Option[HeaderSpec]
