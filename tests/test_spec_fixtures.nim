import std/[json, os, parseutils, strutils, unittest]

import ../src/toon

proc fixturePath(parts: varargs[string]): string =
  result = currentSourcePath().parentDir()
  for part in parts:
    result = result / part

proc loadFixture(parts: varargs[string]): JsonNode =
  parseFile(fixturePath(parts))

proc parseDelimiter(value: string): Delimiter =
  case value
  of "\t":
    delimTab
  of "|":
    delimPipe
  else:
    delimComma

proc decodeOptionsFrom(node: JsonNode): DecodeOptions =
  result = defaultDecodeOptions()
  if node.kind != JObject:
    return
  if node.hasKey("indent"):
    result.indent = node["indent"].getInt()
  if node.hasKey("strict"):
    result.strict = node["strict"].getBool()
  if node.hasKey("expandPaths"):
    let value = node["expandPaths"].getStr()
    result.expandPaths = if value == "safe": pathExpandSafe else: pathExpandOff

proc encodeOptionsFrom(node: JsonNode): EncodeOptions =
  result = defaultEncodeOptions()
  if node.kind != JObject:
    return
  if node.hasKey("indent"):
    result.indent = node["indent"].getInt()
  if node.hasKey("delimiter"):
    result.delimiter = parseDelimiter(node["delimiter"].getStr())
  if node.hasKey("keyFolding"):
    let value = node["keyFolding"].getStr()
    result.keyFolding = if value == "safe": keyFoldSafe else: keyFoldOff
  if node.hasKey("flattenDepth"):
    result.flattenDepth = node["flattenDepth"].getInt()

proc encodeOptionsForInvariant(options: DecodeOptions): EncodeOptions =
  result = defaultEncodeOptions()
  result.indent = options.indent

proc normalizeEncodeInput(input, expected: JsonNode): JsonNode =
  result = input
  if input.kind != JString or expected.kind != JString:
    return

  let token = input.getStr()
  let expectedText = expected.getStr()
  if token != expectedText:
    return

  var intValue: BiggestInt
  try:
    if parseBiggestInt(token, intValue, 0) == token.len:
      return newJInt(intValue)
  except ValueError:
    discard

  var floatValue: float
  try:
    if parseFloat(token, floatValue, 0) == token.len:
      return newJFloat(floatValue)
  except ValueError:
    discard

proc runEncodeFixture(parts: varargs[string]) =
  let path = join(parts, "/")
  let fixture = loadFixture(parts)
  let description = fixture["description"].getStr()
  suite "encode fixture: " & path:
    test description:
      for testCase in fixture["tests"]:
        let name = testCase["name"].getStr()
        let options =
          if testCase.hasKey("options"): encodeOptionsFrom(testCase["options"])
          else: defaultEncodeOptions()
        let input = normalizeEncodeInput(testCase["input"], testCase["expected"])
        let expected = testCase["expected"].getStr()
        let encoded = encode(input, options)
        checkpoint(path & " :: " & name)
        check encoded == expected
        check decode(encoded, defaultDecodeOptions()) == input

proc runDecodeFixture(parts: varargs[string]) =
  let path = join(parts, "/")
  let fixture = loadFixture(parts)
  let description = fixture["description"].getStr()
  suite "decode fixture: " & path:
    test description:
      for testCase in fixture["tests"]:
        let name = testCase["name"].getStr()
        let options =
          if testCase.hasKey("options"): decodeOptionsFrom(testCase["options"])
          else: defaultDecodeOptions()
        let input = testCase["input"].getStr()
        let shouldError = testCase.hasKey("shouldError") and testCase["shouldError"].getBool()
        checkpoint(path & " :: " & name)
        if shouldError:
          expect ToonError:
            discard decode(input, options)
        else:
          let expected = testCase["expected"]
          let decoded = decode(input, options)
          check decoded == expected
          let reencoded = encode(decoded, encodeOptionsForInvariant(options))
          check decode(reencoded, options) == expected

runEncodeFixture("fixtures", "encode", "primitives.json")
runEncodeFixture("fixtures", "encode", "objects.json")
runEncodeFixture("fixtures", "encode", "arrays-tabular.json")
runEncodeFixture("fixtures", "encode", "arrays-nested.json")

runDecodeFixture("fixtures", "decode", "primitives.json")
runDecodeFixture("fixtures", "decode", "numbers.json")
runDecodeFixture("fixtures", "decode", "objects.json")
runDecodeFixture("fixtures", "decode", "arrays-tabular.json")
runDecodeFixture("fixtures", "decode", "arrays-nested.json")
runDecodeFixture("fixtures", "decode", "delimiters.json")
runDecodeFixture("fixtures", "decode", "indentation-errors.json")
runDecodeFixture("fixtures", "decode", "validation-errors.json")
