import std/[math, parseutils, strutils]

import ./errors

proc isQuotedLiteral*(token: string): bool =
  token.len >= 2 and token[0] == '"' and token[^1] == '"'

proc isIdentifierKey*(token: string): bool =
  if token.len == 0:
    return false
  if not (token[0].isAlphaAscii() or token[0] == '_'):
    return false
  for ch in token[1 .. ^1]:
    if not (ch.isAlphaNumeric() or ch in {'_', '.'}):
      return false
  true

proc isIdentifierSegment*(token: string): bool =
  if token.len == 0:
    return false
  if not (token[0].isAlphaAscii() or token[0] == '_'):
    return false
  for ch in token[1 .. ^1]:
    if not (ch.isAlphaNumeric() or ch == '_'):
      return false
  true

proc escapeQuoted*(value: string): string =
  result = newStringOfCap(value.len + 8)
  for ch in value:
    case ch
    of '\\':
      result.add("\\\\")
    of '"':
      result.add("\\\"")
    of '\n':
      result.add("\\n")
    of '\r':
      result.add("\\r")
    of '\t':
      result.add("\\t")
    else:
      result.add(ch)

proc unescapeQuoted*(token: string): string =
  if not isQuotedLiteral(token):
    raise newToonError(teSyntax, "expected quoted string")

  var i = 1
  while i < token.len - 1:
    let ch = token[i]
    if ch == '\\':
      if i + 1 >= token.len - 1:
        raise newToonError(teSyntax, "unterminated escape sequence")
      let next = token[i + 1]
      case next
      of '\\':
        result.add('\\')
      of '"':
        result.add('"')
      of 'n':
        result.add('\n')
      of 'r':
        result.add('\r')
      of 't':
        result.add('\t')
      else:
        raise newToonError(teSyntax, "invalid escape sequence")
      inc(i, 2)
    else:
      result.add(ch)
      inc(i)

proc firstUnquotedIndex*(input: string; target: char): int =
  var inQuote = false
  var escaped = false
  for i, ch in input:
    if escaped:
      escaped = false
      continue
    if inQuote and ch == '\\':
      escaped = true
      continue
    if ch == '"':
      inQuote = not inQuote
      continue
    if ch == target and not inQuote:
      return i
  -1

proc splitDelimited*(input: string; delimiter: char): seq[string] =
  var current = ""
  var inQuote = false
  var escaped = false

  for ch in input:
    if escaped:
      current.add(ch)
      escaped = false
      continue

    if inQuote and ch == '\\':
      current.add(ch)
      escaped = true
      continue

    if ch == '"':
      current.add(ch)
      inQuote = not inQuote
      continue

    if ch == delimiter and not inQuote:
      result.add(current.strip())
      current.setLen(0)
      continue

    current.add(ch)

  result.add(current.strip())

proc tryParseIntExact*(token: string; value: var BiggestInt): bool =
  try:
    let parsed = parseBiggestInt(token, value, 0)
    parsed == token.len
  except ValueError:
    false

proc tryParseFloatExact*(token: string; value: var float): bool =
  try:
    let parsed = parseFloat(token, value, 0)
    parsed == token.len
  except ValueError:
    false

proc hasForbiddenLeadingZero*(token: string): bool =
  if token.len < 2:
    return false
  var start = 0
  if token[0] == '-':
    start = 1
  if start >= token.len - 1:
    return false
  token[start] == '0' and token[start + 1].isDigit

proc isNumericLike*(token: string): bool =
  var intValue: BiggestInt
  if tryParseIntExact(token, intValue):
    return true

  var floatValue: float
  if tryParseFloatExact(token, floatValue):
    return true

  hasForbiddenLeadingZero(token)

proc expandExponent*(value: string): string =
  let ePos = max(value.find('e'), value.find('E'))
  if ePos < 0:
    return value

  let mantissa = value[0 ..< ePos]
  let exponent = parseInt(value[ePos + 1 .. ^1])

  var sign = ""
  var digits = mantissa
  if digits.startsWith("-"):
    sign = "-"
    digits = digits[1 .. ^1]

  let dotPos = digits.find('.')
  var whole = digits
  var frac = ""
  if dotPos >= 0:
    whole = digits[0 ..< dotPos]
    frac = digits[dotPos + 1 .. ^1]

  let rawDigits = whole & frac
  let decimalPos = whole.len + exponent

  if decimalPos <= 0:
    return sign & "0." & repeat('0', -decimalPos) & rawDigits
  if decimalPos >= rawDigits.len:
    return sign & rawDigits & repeat('0', decimalPos - rawDigits.len)
  sign & rawDigits[0 ..< decimalPos] & "." & rawDigits[decimalPos .. ^1]

proc normalizeCanonicalNumber*(value: string): string =
  result = value
  if 'e' in result or 'E' in result:
    result = expandExponent(result)

  if "." in result:
    while result.endsWith("0"):
      result.setLen(result.len - 1)
    if result.endsWith("."):
      result.setLen(result.len - 1)

  if result == "-0":
    return "0"
  if result.startsWith("-0.") and result[3 .. ^1].allCharsInSet({'0'}):
    return "0"

proc scalarLooksAmbiguous*(value: string): bool =
  value in ["true", "false", "null"] or isNumericLike(value)
