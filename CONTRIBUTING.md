# Contributing

## Development

Run the main test suites before sending changes:

```bash
nim c -r tests/test_toon.nim
nim c -r tests/test_spec_fixtures.nim
```

## Scope

- Keep the public API in [src/toon.nim](/home/ops/Project/nim-toon/src/toon.nim) small and stable.
- Prefer adding new fixture coverage under [tests/fixtures](/home/ops/Project/nim-toon/tests/fixtures) when behavior comes from the TOON specification.
- Preserve deterministic encoder output unless a spec change requires otherwise.

## Pull Requests

- Include tests for parser or encoder behavior changes.
- Document any intentionally unsupported spec areas in [README.md](/home/ops/Project/nim-toon/README.md).
