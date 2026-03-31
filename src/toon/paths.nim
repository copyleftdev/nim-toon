import std/[json, strutils]

import ./[errors, options, strings]

proc deepMerge(target: JsonNode; incoming: JsonNode; strict: bool) =
  for key, value in incoming:
    if not target.hasKey(key):
      target[key] = value
      continue

    if target[key].kind == JObject and value.kind == JObject:
      deepMerge(target[key], value, strict)
      continue

    if strict:
      raise newToonError(teConflict, "path expansion conflict at key '" & key & "'")
    target[key] = value

proc expandObject(node: JsonNode; strict: bool): JsonNode

proc expandValue(node: JsonNode; strict: bool): JsonNode =
  case node.kind
  of JObject:
    result = expandObject(node, strict)
  of JArray:
    result = newJArray()
    for item in node.items:
      result.add(expandValue(item, strict))
  else:
    result = node

proc buildPathNode(parts: seq[string]; value: JsonNode): JsonNode =
  if parts.len == 0:
    return value
  result = newJObject()
  result[parts[0]] = buildPathNode(parts[1 .. ^1], value)

proc expandObject(node: JsonNode; strict: bool): JsonNode =
  result = newJObject()
  for key, value in node:
    let expandedValue = expandValue(value, strict)
    let parts = key.split('.')
    var safePath = key.contains('.')
    if safePath:
      for part in parts:
        if not isIdentifierSegment(part):
          safePath = false
          break
    if safePath:
      let pathNode = buildPathNode(parts, expandedValue)
      deepMerge(result, pathNode, strict)
    else:
      if result.hasKey(key) and strict:
        raise newToonError(teConflict, "duplicate key during path expansion: '" & key & "'")
      result[key] = expandedValue

proc applyPathExpansion*(node: JsonNode; options: DecodeOptions): JsonNode =
  if options.expandPaths == pathExpandSafe:
    expandValue(node, options.strict)
  else:
    node
