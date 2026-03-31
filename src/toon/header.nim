import std/[options, strutils]

import ./[errors, options, strings, types]

proc decodeKeyToken(token: string): string =
  let cleaned = token.strip()
  if cleaned.len == 0:
    raise newToonError(teSyntax, "missing key")
  if isQuotedLiteral(cleaned):
    return unescapeQuoted(cleaned)
  cleaned

proc tryParseHeader*(text: string): HeaderResult =
  let colonPos = firstUnquotedIndex(text, ':')
  if colonPos < 0:
    return none(HeaderSpec)

  let head = text[0 ..< colonPos]
  let inline = text[colonPos + 1 .. ^1].strip()
  if head.len == 0:
    return none(HeaderSpec)

  var i = 0
  var key = ""
  var hasKey = false

  if head[0] != '[':
    hasKey = true
    if head[0] == '"':
      let closeQuote = head.rfind('"')
      if closeQuote <= 0:
        return none(HeaderSpec)
      key = unescapeQuoted(head[0 .. closeQuote])
      i = closeQuote + 1
    else:
      let bracketPos = head.find('[')
      if bracketPos <= 0:
        return none(HeaderSpec)
      key = head[0 ..< bracketPos].strip()
      i = bracketPos

  if i >= head.len or head[i] != '[':
    return none(HeaderSpec)

  inc(i)
  let digitsStart = i
  while i < head.len and head[i].isDigit:
    inc(i)
  if digitsStart == i:
    return none(HeaderSpec)
  let digitsEnd = i

  var delimiter = delimComma
  if i < head.len and (head[i] == '\t' or head[i] == '|'):
    delimiter = if head[i] == '\t': delimTab else: delimPipe
    inc(i)

  if i >= head.len or head[i] != ']':
    return none(HeaderSpec)
  let count = parseInt(head[digitsStart ..< digitsEnd])
  inc(i)

  while i < head.len and head[i] == ' ':
    inc(i)

  var fields: seq[string]
  if i < head.len and head[i] == '{':
    let closeBrace = head.rfind('}')
    if closeBrace < i:
      return none(HeaderSpec)
    let between = head[i + 1 ..< closeBrace]
    for field in splitDelimited(between, charOf(delimiter)):
      fields.add(decodeKeyToken(field))
    i = closeBrace + 1

  while i < head.len and head[i] == ' ':
    inc(i)

  if i != head.len:
    return none(HeaderSpec)

  some(HeaderSpec(
    key: key,
    hasKey: hasKey,
    count: count,
    delimiter: delimiter,
    fields: fields,
    inline: inline,
  ))
