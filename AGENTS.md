# grove

A bash CLI (`grove.sh`) plus a Nix flake with its package and home-manager module (`nix/`). Read
`docs/decisions.md` before changing behaviour: it records why each rule is the way it is.

## Related repos

- Depends on: none.
- Used by: home-manager configurations, through `homeManagerModules.default` and the package. They are named
  generically on purpose: grove is public, and the repos that use it may be private. What they rely on is the
  module's options, the generated `<root>/AGENTS.md` text, the `GROVE_*` variables and the CLI's behaviour, which
  hooks depend on: `grove wt new` prints the path as the last line of stdout, and `grove wt rm <path>` refuses
  uncommitted changes and, with a remote, unpushed commits.

## Run

`nix run . -- <command>`, or `./grove.sh <command>` with git and gh on the PATH. Point `GROVE_ROOT` at a scratch
directory to try it without touching real clones.

## Test

- `nix develop -c bats test`: the CLI against a temp `GROVE_ROOT`, local repos and the stub `gh` in `test/stub/`.
  New behaviour gets a test there; the stub grows with any new `gh` call.
- `nix develop -c shellcheck grove.sh test/stub/gh test/helpers.bash`
- `nix flake check`: both of the above in the sandbox, plus the module's generated text (`nix/checks.nix`).

Keep everything generic: no machine names, people, secrets backends or absolute paths outside test fixtures.
