# grove

One clone per repo, at a predictable path, with agent work in sibling worktrees.

```
~/git/
├── AGENTS.md, CLAUDE.md     shared rules for agents (home-manager module)
├── acme/
│   ├── api/                 main checkout, clean on the default branch
│   └── api.wt/
│       ├── agent-fix-login/ branch agent/fix-login
│       └── agent-docs/      branch agent/docs
└── local/
    └── scratch/             repo with no remote, until `grove publish`
```

## Commands

| Command | What it does |
|---|---|
| `grove clone <owner>/<repo>\|<url> [-- <git clone flags>]` | Clone to `<root>/<owner>/<repo>` with GitHub's spelling of owner and name; forks get `upstream`. Prints the path; an existing clone is left alone. |
| `grove new <owner>/<repo> [--public] [-t <template>]` | Create the repo on GitHub (private by default) with an initial commit and push `main`. Refuses repos that already exist. |
| `grove new <repo> [-t <template>]` | Create a local repo with no remote at `<root>/<local owner>/<repo>`. |
| `grove publish <owner> [--public]` | From a local repo: create it on GitHub, push `main` and every `agent/*` branch with a worktree, and move the repo and its worktrees to `<root>/<owner>/`. |
| `grove wt new <branch> [base]` | Create `<repo>.wt/<branch with / → ->` from the current repo and print the path. Reuses an existing local or `origin` branch. |
| `grove wt ls` | Every worktree under the root: unpushed commits (or `local`), clean/dirty, merged. |
| `grove wt rm <path>` | Remove a worktree; refuses uncommitted changes and, with a remote, unpushed commits. |
| `grove wt gc [-n]` | Remove worktrees that are clean, pushed, merged (squash merges included, via `gh`) and untouched for an hour, with no process inside. `-n` only reports. |

New repos start on `main` with one commit, `chore: init`, holding a `README.md`, an `AGENTS.md` skeleton (what it is,
how to run it, how to test it) and a `.gitignore`. With `-t <template>`, `nix flake init -t $GROVE_TEMPLATES#<template>`
runs first and its files win over the defaults.

Repos without `origin` are first-class: `wt new` branches from the local default branch without fetching, `rm` needs
nothing pushed (an unmerged branch is kept), and `gc` uses "merged into the local default branch".

The reasons behind each choice are in [docs/decisions.md](docs/decisions.md).

## Requirements

bash, git, coreutils, findutils, gawk, sed, `column` (util-linux) and an authenticated [GitHub CLI](https://cli.github.com)
for anything that talks to GitHub. `nix` only for `-t`. Detecting processes inside a worktree reads `/proc`, so on
systems without it `gc` and `publish` rely on the one-hour rule alone.

## Configuration

| Variable | Default | |
|---|---|---|
| `GROVE_ROOT` | `$HOME/git` | Where every clone lives. |
| `GROVE_LOCAL_OWNER` | `local` | Owner directory for repos with no remote. |
| `GROVE_DEFAULT_VISIBILITY` | `private` | `private` or `public`, for `new` and `publish`. |
| `GROVE_TEMPLATES` | none | Flake reference for `-t`. |

## Install

Without Nix, put `grove.sh` on your `PATH` as `grove`.

With Nix: `nix run <this flake> -- --help` (for example `nix run .` in a checkout), or add `packages.<system>.grove` to your profile.

### home-manager

```nix
{
  inputs.grove.url = "github:OWNER/grove"; # wherever you get grove from

  # in your home-manager configuration:
  imports = [ inputs.grove.homeManagerModules.default ];
  programs.grove = {
    enable = true;
    # root = "${config.home.homeDirectory}/git";
    # localOwner = "local";
    # defaultVisibility = "private";
    templates = "github:you/templates";
    extraAgentsDoc = ''
      ## This machine

      Run project tools with `devenv shell -- <cmd>`.
    '';
    secrets = {
      command = "with-secrets";
      paths."acme/api"."/stripe/api" = "payments in integration tests";
    };
  };
}
```

The module installs `grove` with those settings as defaults (the environment still wins) and writes the agent
instructions to `<root>/AGENTS.md` and `<root>/CLAUDE.md`. Both hold the full text, built from:

1. `agentsDoc`: the generic rules (layout, worktrees, push at the end of every session, local repos and `grove publish`,
   who decides on merges). `userName`, by default your git `user.name`, is the person named as deciding.
2. A secrets section when `secrets.paths` is non-empty: how to call `secrets.command` and a repo → paths table.
3. `extraAgentsDoc`: your own additions.

## Development

```sh
nix develop -c bats test     # tests: temp GROVE_ROOT, local repos, a stub gh; never touches GitHub
nix develop -c shellcheck grove.sh test/stub/gh test/helpers.bash
nix flake check              # both of the above in the sandbox, plus the module's generated text
```

## License

[MIT](LICENSE)
