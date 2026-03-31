import std/[json, os, strutils, unittest]

import ../src/toon

proc fixturePath(name: string): string =
  currentSourcePath().parentDir() / "fixtures" / name

proc loadJsonFixture(name: string): JsonNode =
  parseFile(fixturePath(name))

suite "toon":
  test "encodes and decodes primitive arrays":
    let node = %*{"tags": ["reading", "gaming", "coding"]}
    let encoded = encode(node)
    check encoded == "tags[3]: reading,gaming,coding"
    check decode(encoded) == node

  test "encodes tabular arrays":
    let node = %*{
      "items": [
        {"sku": "A1", "qty": 2, "price": 9.99},
        {"sku": "B2", "qty": 1, "price": 14.5},
      ]
    }
    let expected = "items[2]{sku,qty,price}:\n  A1,2,9.99\n  B2,1,14.5"
    check encode(node) == expected
    check decode(expected) == node

  test "decodes root arrays and quoted ambiguity":
    let value = decode("[5]: x,y,\"true\",true,10")
    check value == %*["x", "y", "true", true, 10]

  test "handles nested arrays and list objects":
    let input = "items[2]:\n  - id: 1\n    name: First\n  - [2]: a,b"
    let expected = %*{
      "items": [
        {"id": 1, "name": "First"},
        ["a", "b"],
      ]
    }
    check decode(input) == expected

  test "handles tabular arrays as first list-item field":
    let input = "items[1]:\n  - users[2]{id,name}:\n      1,Ada\n      2,Bob\n    status: active"
    let expected = %*{
      "items": [
        {
          "users": [{"id": 1, "name": "Ada"}, {"id": 2, "name": "Bob"}],
          "status": "active",
        }
      ]
    }
    check decode(input) == expected

  test "supports pipe and tab delimiters":
    let tabValue = decode("items[2\t]{id\tname}:\n  1\tAda\n  2\tBob")
    check tabValue == %*{"items": [{"id": 1, "name": "Ada"}, {"id": 2, "name": "Bob"}]}
    var pipeOptions = defaultEncodeOptions()
    pipeOptions.delimiter = delimPipe
    let pipeEncoded = encode(%*{"tags": ["a|b", "c"]}, pipeOptions)
    check pipeEncoded == "tags[2|]: \"a|b\"|c"

  test "accepts empty documents as empty objects":
    check decode("") == %*{}

  test "encodes mixed arrays in list form":
    let node = %*{
      "items": [
        1,
        {"a": 1},
        ["x", "y"],
      ]
    }
    let expected = "items[3]:\n  - 1\n  - a: 1\n  - [2]: x,y"
    check encode(node) == expected
    check decode(expected) == node

  test "expands dotted paths in safe mode":
    var options = defaultDecodeOptions()
    options.expandPaths = pathExpandSafe
    let decoded = decode("user.profile.name: Ada\nuser.profile.active: true", options)
    check decoded == %*{"user": {"profile": {"name": "Ada", "active": true}}}

  test "round trips a chaos object with mixed complexity":
    let node = loadJsonFixture("chaos.json")
    let encoded = encode(node)
    check "inventory[2]{sku,qty,\"unit price\"}:" in encoded
    check "- steps[2]{id,label}:" in encoded
    check "flags[3]: alpha,\"true\",\"- item\"" in encoded
    check "events[4]:" in encoded
    check decode(encoded) == node

  test "round trips a chaos object with pipe delimiter":
    let node = loadJsonFixture("chaos.json")
    var options = defaultEncodeOptions()
    options.delimiter = delimPipe
    let encoded = encode(node, options)
    check "inventory[2|]{sku|qty|\"unit price\"}:" in encoded
    check "- steps[2|]{id|label}:" in encoded
    check "checks[2|]:" in encoded
    check decode(encoded) == node

  test "rejects strict validation failures":
    expect ToonError:
      discard decode("tags[2]: a,b,c")
    expect ToonError:
      discard decode("\"a\\x\"")
