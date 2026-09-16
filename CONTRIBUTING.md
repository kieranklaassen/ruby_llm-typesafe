# Contributing to ruby_llm-typesafe

This gem follows the conventions of [RubyLLM](https://github.com/crmne/ruby_llm). A provider knows where to talk and who you are, a protocol knows how to talk, and every behavior ships with a spec. Read RubyLLM's [AGENTS.md](https://github.com/crmne/ruby_llm/blob/main/AGENTS.md) and [custom providers guide](https://rubyllm.com/custom-providers/) before making larger changes.

## Did you find a bug?

* Search the [issues](https://github.com/kieranklaassen/ruby_llm-typesafe/issues) first.
* If none matches, [open a new one](https://github.com/kieranklaassen/ruby_llm-typesafe/issues/new) with a clear title, a description, and a code sample that reproduces it.
* Check whether the behavior comes from this gem, from RubyLLM, or from the TypeSafe API before opening the issue.

## Did you write a patch?

* Open a pull request that describes the problem and the solution, and links the issue if there is one.
* Run `overcommit --install` after cloning so RuboCop, Flay, ArchSpec, RSpec, and gitleaks gate every commit.
* Keep the diff focused. No drive-by refactors or style sweeps outside the lines you touch.

## Scope

TypeSafe's System One models return typed judgments, not generated text. This gem is therefore structured output only. Changes that turn it into a chat, completion, streaming, or tool-calling provider are out of scope. Open an issue first if you think an exception is warranted.

Wire vocabulary stays in `lib/ruby_llm/protocols/system_one`; authentication, endpoints, the model catalog, and the question builder stay in `lib/ruby_llm/providers/typesafe`. `Archspec.rb` fails the build when they mix.

## Quick start

```bash
git clone https://github.com/kieranklaassen/ruby_llm-typesafe.git && cd ruby_llm-typesafe
bin/setup
overcommit --install
cp .env.example .env   # add your TYPESAFE_API_KEY for live recording
bundle exec rake       # rubocop, flay, archspec, rspec
```

## Testing

```bash
bundle exec rspec --tag ~live   # unit specs, no cassettes or API key needed
bundle exec rspec               # everything; :live specs replay the committed cassettes
bundle exec rake vcr:record     # re-record every cassette against the live API (needs TYPESAFE_API_KEY)
bundle exec rake models         # refresh models.json from GET /v1/models (needs TYPESAFE_API_KEY)
```

Specs tagged `:live` talk to TypeSafe through VCR cassettes in `spec/fixtures/vcr_cassettes`. Everything else is a plain unit test with WebMock. Cassette names derive from the example's full description, and a failing `:live` example deletes its cassette so the next run records against the real API.

The API key lives only in your environment (`TYPESAFE_API_KEY`). VCR replaces it with `<TYPESAFE_API_KEY>` and the Authorization header with `Bearer <AUTH_TOKEN>` before writing a cassette. Always check cassettes for leaked keys before committing; gitleaks runs in the pre-commit hook and in CI.

## Releasing

1. Update `VERSION` in `lib/ruby_llm/providers/typesafe.rb`, the version in `ruby_llm-typesafe.gemspec`, and `CHANGELOG.md`.
2. Commit, then tag `vX.Y.Z` and push the tag. The release workflow runs the full suite, builds the gem, and publishes it to RubyGems.
