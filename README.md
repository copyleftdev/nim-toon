# nim-toon

`nim-toon` is a modular Nim implementation of the TOON (Token-Oriented Object Notation) format.

Status: early public release candidate with fixture-backed conformance coverage.

It provides:

- `encode(JsonNode): string`
- `decode(string): JsonNode`
- configurable indentation and delimiter options
- strict decoding with array-length and indentation checks
- optional safe dotted-path expansion on decode
- fixture-backed conformance tests against upstream TOON spec cases

## Install

```bash
nimble install
```

If your environment restricts `~/.nimble`, set `NIMBLE_DIR` to a writable directory before running `nimble`.

## Usage

```nim
import std/json
import toon

let value = %*{
  "users": [
    {"id": 1, "name": "Ada"},
    {"id": 2, "name": "Bob"},
  ]
}

let text = encode(value)
let decoded = decode(text)
```

## Test Coverage

The repository includes:

- handwritten behavioral tests in [tests/test_toon.nim](/home/ops/Project/nim-toon/tests/test_toon.nim)
- fixture-driven spec tests in [tests/test_spec_fixtures.nim](/home/ops/Project/nim-toon/tests/test_spec_fixtures.nim)
- external JSON fixtures in [tests/fixtures](/home/ops/Project/nim-toon/tests/fixtures)

Run them with:

```bash
nim c -r tests/test_toon.nim
nim c -r tests/test_spec_fixtures.nim
```

## Module layout

- [src/toon.nim](/home/ops/Project/nim-toon/src/toon.nim): public API
- [src/toon/encoder.nim](/home/ops/Project/nim-toon/src/toon/encoder.nim): JSON-to-TOON serializer
- [src/toon/parser.nim](/home/ops/Project/nim-toon/src/toon/parser.nim): TOON decoder
- [src/toon/header.nim](/home/ops/Project/nim-toon/src/toon/header.nim): header parsing
- [src/toon/strings.nim](/home/ops/Project/nim-toon/src/toon/strings.nim): quoting, escaping, delimiter splitting
- [src/toon/paths.nim](/home/ops/Project/nim-toon/src/toon/paths.nim): optional safe path expansion

## Numeric policy

Encoding emits canonical decimal strings without exponent notation. Decoding accepts exponent forms, but values outside Nim's native numeric range are not promoted to arbitrary-precision types; callers that need exact big-number handling should keep those values as strings before encoding.

## Publishing Notes

For GitHub publication, the repository already includes:

- [LICENSE](/home/ops/Project/nim-toon/LICENSE)
- [CONTRIBUTING.md](/home/ops/Project/nim-toon/CONTRIBUTING.md)
- [ci.yml](/home/ops/Project/nim-toon/.github/workflows/ci.yml)

## Contact

Maintainer: `copyleftdev <copyleftdev@users.noreply.github.com>`
