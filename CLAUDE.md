# Notes for Claude sessions working on this repository

## single-file is built by CI: never by hand

The `single-file` branch (the whole configuration as one `init.lua`) is
rebuilt by a GitHub Action, `.github/workflows/single-file.yml`, on every
push to `windows`. It runs `scripts/bundle.lua` and commits the result to
`single-file` as `github-actions[bot]`.

- **Do not** run `nvim -l scripts/bundle.lua` to commit or push to
  `single-file`, and do not push to `single-file` at all. A manual push
  races the Action and one of the two pushes fails.
- To get a fresh `single-file`, push to `windows` (normally by merging
  `main` into it). To rebuild without a new commit: GitHub → Actions →
  "Rebuild single-file" → Run workflow.
- Running `nvim -l scripts/bundle.lua` locally only to check that the bundle
  builds is fine; do not commit its output (`pure.lua` is ignored).
- To check the result, look at the Action's run and the new commit on
  `single-file`.

## Branches

- Work happens on a feature branch, then: merge it into `main`, then merge
  `main` into `windows` (merge commits, no rebase or force-push on these).
  Pushing `windows` is what updates `single-file` (above).
- `windows` is `main` plus a Windows-only block in `init.lua`.
- More than one Claude session may push to the same branches: `git fetch`
  and fast-forward before editing, and again before merging.

## Conventions

- Code, comments, commit messages and docs in English.
- When a module changes, update its page in `docs/` in the same commit
  (see `docs/README.md`).
- Nothing personal in the repository: tokens, credentials and the vault
  path live in `stdpath('data')`.
- Before committing, check that every module still loads: start Neovim
  headless and verify each `lua/**/*.lua` module is in `package.loaded`
  (a syntax error in one module does not stop Neovim from starting).
