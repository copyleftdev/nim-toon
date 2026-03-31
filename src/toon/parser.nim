import std/[json, math, options, strutils]

import ./[errors, header, options, paths, strings, types]

proc fail(state: ParserState; kind: ToonErrorKind; message: string; line = 0) {.noreturn.} =
  let lineNumber = if line > 0: line else: (if state.index < state.lines.len: state.lines[state.index].number else: 0)
  raise newToonError(kind, message, lineNumber)

proc lex(input: string; options: DecodeOptions): seq[LineInfo] =
  let normalized = input.replace("\r\n", "\n").replace('\r', '\n')
  for idx, rawLine in pairs(normalized.split('\n')):
    var indentSpaces = 0
    var tabIndent = false
    var cursor = 0

    while cursor < rawLine.len and (rawLine[cursor] == ' ' or rawLine[cursor] == '\t'):
      if rawLine[cursor] == '\t':
        tabIndent = true
        indentSpaces += options.indent
      else:
        inc(indentSpaces)
      inc(cursor)

    let content = rawLine[cursor .. ^1]
    let isBlank = content.strip().len == 0

    if not isBlank and tabIndent and options.strict:
      raise newToonError(teIndentation, "tabs are not allowed in indentation", idx + 1)
    if not isBlank and options.strict and indentSpaces mod max(options.indent, 1) != 0:
      raise newToonError(teIndentation, "indentation is not a multiple of the configured indent size", idx + 1)

    let depth =
      if isBlank:
        0
      elif options.strict:
        indentSpaces div max(options.indent, 1)
      else:
        indentSpaces div max(options.indent, 1)

    result.add(LineInfo(
      number: idx + 1,
      raw: rawLine,
      content: content,
      depth: depth,
      indentSpaces: indentSpaces,
      isBlank: isBlank,
    ))

proc firstNonBlankAtOrAfter(state: ParserState; start: int): int =
  result = start
  while result < state.lines.len and state.lines[result].isBlank:
    inc(result)

proc isRowLine(content: string; delimiter: Delimiter): bool =
  let colonPos = firstUnquotedIndex(content, ':')
  let delimPos = firstUnquotedIndex(content, charOf(delimiter))
  if colonPos < 0:
    return true
  if delimPos >= 0 and delimPos < colonPos:
    return true
  false

proc decodeKeyToken(token: string): string =
  let cleaned = token.strip()
  if cleaned.len == 0:
    raise newToonError(teSyntax, "missing key")
  if isQuotedLiteral(cleaned):
    return unescapeQuoted(cleaned)
  cleaned

proc decodeScalar(token: string): JsonNode =
  let cleaned = token.strip()
  if cleaned.len == 0:
    return newJString("")
  if cleaned[0] == '"' and not isQuotedLiteral(cleaned):
    raise newToonError(teSyntax, "unterminated string literal")
  if isQuotedLiteral(cleaned):
    return newJString(unescapeQuoted(cleaned))

  case cleaned
  of "true":
    return newJBool(true)
  of "false":
    return newJBool(false)
  of "null":
    return newJNull()
  else:
    discard

  if not hasForbiddenLeadingZero(cleaned):
    var intValue: BiggestInt
    if tryParseIntExact(cleaned, intValue):
      if intValue == 0:
        return newJInt(0)
      return newJInt(intValue)

    var floatValue: float
    if tryParseFloatExact(cleaned, floatValue) and classify(floatValue) in {fcZero, fcNegZero, fcSubnormal, fcNormal}:
      if floatValue == 0.0:
        return newJInt(0)
      if abs(floatValue) <= float(high(BiggestInt)) and floatValue == trunc(floatValue):
        return newJInt(BiggestInt(floatValue))
      return newJFloat(floatValue)

  newJString(cleaned)

proc parseArrayBody(state: var ParserState; spec: HeaderSpec; headerDepth, childDepth: int): JsonNode
proc parseObject(state: var ParserState; depth: int): JsonNode
proc parseFieldInto(state: var ParserState; destination: JsonNode; depth: int)

proc parseTabularRows(
  state: var ParserState;
  spec: HeaderSpec;
  rowDepth: int;
): JsonNode =
  result = newJArray()
  while state.index < state.lines.len:
    let line = state.lines[state.index]
    if line.isBlank:
      if state.options.strict:
        state.fail(teStructure, "blank lines are not allowed inside arrays", line.number)
      inc(state.index)
      continue
    if line.depth < rowDepth:
      break
    if line.depth > rowDepth:
      state.fail(teIndentation, "unexpected indentation inside tabular array", line.number)
    if not isRowLine(line.content, spec.delimiter):
      break

    let cells = splitDelimited(line.content, charOf(spec.delimiter))
    if cells.len != spec.fields.len:
      state.fail(teValidation, "tabular row width does not match declared field count", line.number)

    let row = newJObject()
    for idx, field in spec.fields:
      row[field] = decodeScalar(cells[idx])
    result.add(row)
    inc(state.index)

  if state.options.strict and result.len != spec.count:
    state.fail(teValidation, "tabular row count does not match declared array length")

proc parseListItemObjectFromField(
  state: var ParserState;
  depth: int;
  seed: string;
): JsonNode =
  result = newJObject()
  let colonPos = firstUnquotedIndex(seed, ':')
  if colonPos < 0:
    state.fail(teSyntax, "missing colon in object list item")

  let key = decodeKeyToken(seed[0 ..< colonPos])
  let rest = seed[colonPos + 1 .. ^1].strip()
  if rest.len == 0:
    let nextIndex = firstNonBlankAtOrAfter(state, state.index)
    if nextIndex < state.lines.len and state.lines[nextIndex].depth > depth + 1:
      result[key] = parseObject(state, depth + 2)
    else:
      result[key] = newJObject()
  else:
    result[key] = decodeScalar(rest)

  while state.index < state.lines.len:
    let line = state.lines[state.index]
    if line.isBlank:
      inc(state.index)
      continue
    if line.depth <= depth:
      break
    if line.depth != depth + 1:
      state.fail(teIndentation, "unexpected indentation in object list item", line.number)
    parseFieldInto(state, result, depth + 1)

proc parseListItemObjectFromHeader(
  state: var ParserState;
  depth: int;
  spec: HeaderSpec;
): JsonNode =
  result = newJObject()
  if spec.fields.len > 0:
    result[spec.key] = parseTabularRows(state, spec, depth + 2)
  else:
    result[spec.key] = parseArrayBody(state, spec, depth + 1, depth + 2)

  while state.index < state.lines.len:
    let line = state.lines[state.index]
    if line.isBlank:
      inc(state.index)
      continue
    if line.depth <= depth:
      break
    if line.depth != depth + 1:
      state.fail(teIndentation, "unexpected indentation in object list item", line.number)
    parseFieldInto(state, result, depth + 1)

proc parseListArray(
  state: var ParserState;
  spec: HeaderSpec;
  itemDepth: int;
): JsonNode =
  result = newJArray()

  while state.index < state.lines.len:
    let line = state.lines[state.index]
    if line.isBlank:
      if state.options.strict:
        state.fail(teStructure, "blank lines are not allowed inside arrays", line.number)
      inc(state.index)
      continue
    if line.depth < itemDepth:
      break
    if line.depth > itemDepth:
      state.fail(teIndentation, "unexpected indentation inside array", line.number)
    if not line.content.startsWith("-"):
      break

    let rest =
      if line.content == "-":
        ""
      elif line.content.startsWith("- "):
        line.content[2 .. ^1]
      else:
        line.content[1 .. ^1].strip()

    inc(state.index)
    if rest.len == 0:
      result.add(newJObject())
      continue

    let rootHeader = tryParseHeader(rest)
    if rootHeader.isSome and not rootHeader.get.hasKey:
      result.add(parseArrayBody(state, rootHeader.get, itemDepth, itemDepth + 1))
      continue

    let fieldHeader = tryParseHeader(rest)
    if fieldHeader.isSome and fieldHeader.get.hasKey:
      result.add(parseListItemObjectFromHeader(state, itemDepth, fieldHeader.get))
      continue

    if firstUnquotedIndex(rest, ':') >= 0:
      result.add(parseListItemObjectFromField(state, itemDepth, rest))
      continue

    result.add(decodeScalar(rest))

  if state.options.strict and result.len != spec.count:
    state.fail(teValidation, "array item count does not match declared array length")

proc parseArrayBody(state: var ParserState; spec: HeaderSpec; headerDepth, childDepth: int): JsonNode =
  if spec.fields.len > 0:
    if spec.inline.len > 0:
      state.fail(teSyntax, "tabular headers cannot have inline values")
    return parseTabularRows(state, spec, childDepth)

  if spec.inline.len > 0:
    result = newJArray()
    for token in splitDelimited(spec.inline, charOf(spec.delimiter)):
      result.add(decodeScalar(token))
    if state.options.strict and result.len != spec.count:
      state.fail(teValidation, "inline array width does not match declared array length")
    return result

  let nextIndex = firstNonBlankAtOrAfter(state, state.index)
  if nextIndex >= state.lines.len or state.lines[nextIndex].depth <= headerDepth:
    result = newJArray()
    if state.options.strict and spec.count != 0:
      state.fail(teValidation, "array body is shorter than declared array length")
    return result

  if state.lines[nextIndex].depth != childDepth:
    state.fail(teIndentation, "unexpected indentation under array header", state.lines[nextIndex].number)

  if state.lines[nextIndex].content.startsWith("-"):
    return parseListArray(state, spec, childDepth)

  state.fail(teStructure, "non-tabular arrays must use list items", state.lines[nextIndex].number)

proc parseFieldInto(state: var ParserState; destination: JsonNode; depth: int) =
  let line = state.lines[state.index]
  if line.depth != depth:
    state.fail(teIndentation, "unexpected object field indentation", line.number)
  if line.content.startsWith("-"):
    state.fail(teStructure, "list item found where object field was expected", line.number)

  let headerSpec = tryParseHeader(line.content)
  if headerSpec.isSome and headerSpec.get.hasKey:
    inc(state.index)
    destination[headerSpec.get.key] = parseArrayBody(state, headerSpec.get, depth, depth + 1)
    return

  let colonPos = firstUnquotedIndex(line.content, ':')
  if colonPos < 0:
    state.fail(teSyntax, "missing colon in object field", line.number)

  let key = decodeKeyToken(line.content[0 ..< colonPos])
  let rest = line.content[colonPos + 1 .. ^1].strip()
  inc(state.index)

  if rest.len == 0:
    let nextIndex = firstNonBlankAtOrAfter(state, state.index)
    if nextIndex < state.lines.len and state.lines[nextIndex].depth > depth:
      destination[key] = parseObject(state, depth + 1)
    else:
      destination[key] = newJObject()
  else:
    destination[key] = decodeScalar(rest)

proc parseObject(state: var ParserState; depth: int): JsonNode =
  result = newJObject()
  while state.index < state.lines.len:
    let line = state.lines[state.index]
    if line.isBlank:
      inc(state.index)
      continue
    if line.depth < depth:
      break
    if line.depth > depth:
      state.fail(teIndentation, "unexpected indentation in object", line.number)
    parseFieldInto(state, result, depth)

proc decodeRoot(lines: seq[LineInfo]; options: DecodeOptions): JsonNode =
  var state = ParserState(lines: lines, options: options)
  let firstIndex = firstNonBlankAtOrAfter(state, 0)
  if firstIndex >= lines.len:
    return newJObject()

  state.index = firstIndex
  let firstLine = lines[firstIndex]
  let rootHeader = tryParseHeader(firstLine.content)
  if rootHeader.isSome and not rootHeader.get.hasKey and firstLine.depth == 0:
    inc(state.index)
    return parseArrayBody(state, rootHeader.get, 0, 1)

  var depthZeroNonBlank = 0
  for line in lines:
    if not line.isBlank and line.depth == 0:
      inc(depthZeroNonBlank)

  if depthZeroNonBlank == 1 and firstUnquotedIndex(firstLine.content, ':') < 0:
    return decodeScalar(firstLine.content)

  result = parseObject(state, 0)

proc decodeToon*(input: string; options = defaultDecodeOptions()): JsonNode =
  let parsed = decodeRoot(lex(input, options), options)
  applyPathExpansion(parsed, options)
