# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-16

### Added

- `:typesafe` provider for RubyLLM 2 (`>= 2.0.0.rc3, < 3`) that evaluates state against TypeSafe's System One endpoint (`POST /v1/systemone`).
- `RubyLLM::Providers::TypeSafe::Schema`, a builder for batched Noul, Choice, and Score questions that plugs into `Chat#with_schema` and validates ids, instructions, and criteria before any request.
- `RubyLLM::Protocols::SystemOne`, the wire format. The latest user message is the state, or an explicit `state` from `with_provider_options`. JSON object or array messages become structured state. The typed `answers` map comes back through `Message#parsed` with the response model, token usage, and raw HTTP response.
- Packaged `models.json` catalog (`jev-latest`, `jev-preview`) refreshed from `GET /v1/models` with `rake models`.
- Readable error messages for TypeSafe's `detail` error bodies, mapped onto RubyLLM's error classes (401, 400, 422, 429, 529, 5xx) with RubyLLM's bounded retries and `Retry-After` handling.
- TypeSafe is structured output only, so plain chat, ordinary JSON Schemas, streaming, tools, and attachments raise a `RubyLLM::Error` before any request.

[Unreleased]: https://github.com/kieranklaassen/ruby_llm-typesafe/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kieranklaassen/ruby_llm-typesafe/releases/tag/v0.1.0
