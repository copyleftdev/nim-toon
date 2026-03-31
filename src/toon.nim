import std/json

import toon/[encoder, errors, options, parser]

export json
export errors
export options

proc encode*(node: JsonNode; options = defaultEncodeOptions()): string =
  encodeToon(node, options)

proc decode*(input: string; options = defaultDecodeOptions()): JsonNode =
  decodeToon(input, options)
