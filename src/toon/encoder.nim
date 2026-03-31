import std/[json, math, sequtils, strutils]

import ./[options, strings]

proc canonicalNumber(node: JsonNode): string =
  case node.kind
  of JInt:
    $node.getBiggestInt()
  of JFloat:
    if classify(node.getFloat()) in {fcInf, fcNegInf, fcNan}:
      "null"
    else:
      normalizeCanonicalNumber($node.getFloat())
  else:
    ""

proc encodeKey(key: string): string =
  if isIdentifierKey(key):
    key
  else:
    "\"" & escapeQuoted(key) & "\""

proc shouldQuote(value: string; delimiter: char): bool =
  value.len == 0 or
  value[0].isSpaceAscii() or
  value[^1].isSpaceAscii() or
  scalarLooksAmbiguous(value) or
  value.contains(':') or
  value.contains('"') or
  value.contains('\\') or
  value.contains('[') or
  value.contains(']') or
  value.contains('{') or
  value.contains('}') or
  value.contains('\n') or
  value.contains('\r') or
  value.contains('\t') or
  value.contains(delimiter) or
  value == "-" or
  value.startsWith("-")

proc encodeStringValue(value: string; delimiter: char): string =
  if shouldQuote(value, delimiter):
    "\"" & escapeQuoted(value) & "\""
  else:
    value

proc encodeScalar(node: JsonNode; delimiter: char): string =
  case node.kind
  of JString:
    encodeStringValue(node.getStr(), delimiter)
  of JInt, JFloat:
    canonicalNumber(node)
  of JBool:
    if node.getBool(): "true" else: "false"
  of JNull:
    "null"
  else:
    raise newException(ValueError, "expected scalar JSON node")

proc arrayHeader(
  key: string;
  hasKey: bool;
  count: int;
  delimiter: Delimiter;
  fields: seq[string] = @[];
): string =
  result = ""
  if hasKey:
    result.add(encodeKey(key))
  result.add("[")
  result.add($count)
  result.add(bracketSuffix(delimiter))
  result.add("]")
  if fields.len > 0:
    result.add("{")
    result.add(fields.mapIt(encodeKey(it)).join($charOf(delimiter)))
    result.add("}")
  result.add(":")

proc isScalar(node: JsonNode): bool =
  node.kind in {JString, JInt, JFloat, JBool, JNull}

proc isPrimitiveArray(node: JsonNode): bool =
  if node.kind != JArray:
    return false
  for item in node:
    if not isScalar(item):
      return false
  true

proc isUniformTabular(node: JsonNode; fields: var seq[string]): bool =
  if node.kind != JArray or node.len == 0:
    return false
  if node[0].kind != JObject:
    return false

  fields = @[]
  for key, _ in node[0]:
    fields.add(key)

  for item in node:
    if item.kind != JObject:
      return false
    if item.len != fields.len:
      return false
    for field in fields:
      if not item.hasKey(field) or not isScalar(item[field]):
        return false
  true

proc isPrimitiveArrayArray(node: JsonNode): bool =
  if node.kind != JArray or node.len == 0:
    return false
  for item in node:
    if not isPrimitiveArray(item):
      return false
  true

proc appendArray(
  node: JsonNode;
  lines: var seq[string];
  depth: int;
  options: EncodeOptions;
  key = "";
  hasKey = true;
)

proc appendArrayChildren(node: JsonNode; lines: var seq[string]; depth: int; options: EncodeOptions)
proc appendObject(node: JsonNode; lines: var seq[string]; depth: int; options: EncodeOptions)

proc appendListItem(node: JsonNode; lines: var seq[string]; depth: int; options: EncodeOptions) =
  let prefix = repeat(' ', depth * options.indent)
  case node.kind
  of JString, JInt, JFloat, JBool, JNull:
    lines.add(prefix & "- " & encodeScalar(node, charOf(options.delimiter)))
  of JArray:
    let header = arrayHeader("", false, node.len, options.delimiter)
    if isPrimitiveArray(node):
      let values = toSeq(node).mapIt(encodeScalar(it, charOf(options.delimiter))).join($charOf(options.delimiter))
      lines.add(prefix & "- " & header & (if values.len > 0: " " & values else: ""))
    else:
      lines.add(prefix & "- " & header)
      appendArrayChildren(node, lines, depth + 1, options)
  of JObject:
    if node.len == 0:
      lines.add(prefix & "-")
      return

    var pairs: seq[(string, JsonNode)]
    for key, value in node:
      pairs.add((key, value))

    let (firstKey, firstValue) = pairs[0]
    if firstValue.kind == JArray:
      var fields: seq[string]
      if isUniformTabular(firstValue, fields):
        lines.add(prefix & "- " & arrayHeader(firstKey, true, firstValue.len, options.delimiter, fields))
        for row in firstValue:
          let cells = fields.mapIt(encodeScalar(row[it], charOf(options.delimiter))).join($charOf(options.delimiter))
          lines.add(repeat(' ', (depth + 2) * options.indent) & cells)
        for idx in 1 ..< pairs.len:
          let pair = pairs[idx]
          if pair[1].kind == JObject and pair[1].len > 0:
            lines.add(repeat(' ', (depth + 1) * options.indent) & encodeKey(pair[0]) & ":")
            appendObject(pair[1], lines, depth + 2, options)
          elif pair[1].kind == JObject:
            lines.add(repeat(' ', (depth + 1) * options.indent) & encodeKey(pair[0]) & ":")
          elif pair[1].kind == JArray:
            appendArray(pair[1], lines, depth + 1, options, pair[0], true)
          else:
            lines.add(repeat(' ', (depth + 1) * options.indent) & encodeKey(pair[0]) & ": " &
              encodeScalar(pair[1], charOf(options.delimiter)))
        return

    let firstPrefix = prefix & "- "
    if firstValue.kind == JObject and firstValue.len > 0:
      lines.add(firstPrefix & encodeKey(firstKey) & ":")
      appendObject(firstValue, lines, depth + 2, options)
    elif firstValue.kind == JObject:
      lines.add(firstPrefix & encodeKey(firstKey) & ":")
    elif firstValue.kind == JArray:
      var temp: seq[string]
      appendArray(firstValue, temp, depth, options, firstKey, true)
      if temp.len > 0:
        temp[0] = firstPrefix & temp[0][prefix.len .. ^1]
      for idx in 1 ..< temp.len:
        temp[idx] = repeat(' ', options.indent) & temp[idx]
      lines.add(temp)
    else:
      lines.add(firstPrefix & encodeKey(firstKey) & ": " & encodeScalar(firstValue, charOf(options.delimiter)))

    for idx in 1 ..< pairs.len:
      let pair = pairs[idx]
      if pair[1].kind == JObject and pair[1].len > 0:
        lines.add(repeat(' ', (depth + 1) * options.indent) & encodeKey(pair[0]) & ":")
        appendObject(pair[1], lines, depth + 2, options)
      elif pair[1].kind == JObject:
        lines.add(repeat(' ', (depth + 1) * options.indent) & encodeKey(pair[0]) & ":")
      elif pair[1].kind == JArray:
        appendArray(pair[1], lines, depth + 1, options, pair[0], true)
      else:
        lines.add(repeat(' ', (depth + 1) * options.indent) & encodeKey(pair[0]) & ": " &
          encodeScalar(pair[1], charOf(options.delimiter)))

proc appendArray(
  node: JsonNode;
  lines: var seq[string];
  depth: int;
  options: EncodeOptions;
  key = "";
  hasKey = true;
) =
  let prefix = repeat(' ', depth * options.indent)
  var fields: seq[string]
  let header =
    if isUniformTabular(node, fields):
      arrayHeader(key, hasKey, node.len, options.delimiter, fields)
    else:
      arrayHeader(key, hasKey, node.len, options.delimiter)

  if isPrimitiveArray(node):
    let values = toSeq(node).mapIt(encodeScalar(it, charOf(options.delimiter))).join($charOf(options.delimiter))
    lines.add(prefix & header & (if values.len > 0: " " & values else: ""))
    return

  lines.add(prefix & header)
  appendArrayChildren(node, lines, depth + 1, options)

proc appendArrayChildren(node: JsonNode; lines: var seq[string]; depth: int; options: EncodeOptions) =
  var fields: seq[string]
  if isUniformTabular(node, fields):
    for row in node:
      let cells = fields.mapIt(encodeScalar(row[it], charOf(options.delimiter))).join($charOf(options.delimiter))
      lines.add(repeat(' ', depth * options.indent) & cells)
    return

  if isPrimitiveArrayArray(node):
    for item in node:
      let innerHeader = arrayHeader("", false, item.len, options.delimiter)
      let values = toSeq(item).mapIt(encodeScalar(it, charOf(options.delimiter))).join($charOf(options.delimiter))
      lines.add(repeat(' ', depth * options.indent) & "- " & innerHeader &
        (if values.len > 0: " " & values else: ""))
    return

  for item in node:
    appendListItem(item, lines, depth, options)

proc appendObject(node: JsonNode; lines: var seq[string]; depth: int; options: EncodeOptions) =
  for key, value in node:
    let prefix = repeat(' ', depth * options.indent)
    case value.kind
    of JString, JInt, JFloat, JBool, JNull:
      lines.add(prefix & encodeKey(key) & ": " & encodeScalar(value, charOf(options.delimiter)))
    of JObject:
      lines.add(prefix & encodeKey(key) & ":")
      if value.len > 0:
        appendObject(value, lines, depth + 1, options)
    of JArray:
      appendArray(value, lines, depth, options, key, true)

proc encodeToon*(node: JsonNode; options = defaultEncodeOptions()): string =
  var lines: seq[string]
  case node.kind
  of JObject:
    if node.len == 0:
      return ""
    appendObject(node, lines, 0, options)
  of JArray:
    appendArray(node, lines, 0, options, "", false)
  else:
    lines.add(encodeScalar(node, charOf(options.delimiter)))
  lines.join("\n")
