# Decisions

Records of the choices behind grove's shape. Each one says what was decided and why; read them before "fixing"
something that looks odd.

## 1. One clone per repo at `<root>/<owner>/<repo>`

Every repository has exactly one clone, at a path derived from its GitHub owner and name as GitHub spells them (case
included), not as they were typed. Forks live under the owner of `origin`, with `upstream` pointing at the parent.
A fixed, predictable path lets people, scripts and agents find a repo without searching, and makes "is this cloned
already?" a single `test -e`. There is no host level (`github.com/`): grove only targets GitHub.

## 2. Work happens in sibling worktrees, never in the main checkout

The main checkout stays clean on the default branch and is only the base for worktrees. Work happens in
`<repo>.wt/<branch with / replaced by ->`, next to the repo rather than inside it, so worktrees don't show up as
untracked files, editors and file watchers of the main checkout don't see them, and the whole tree of a repo can be
listed or removed in one place. Several agents can work on the same repo at once, each in its own worktree and branch.

## 3. Agent branches are `agent/<topic>`

The prefix tells a human at a glance which branches an agent created, and gives `publish` a well-defined set of
branches to carry over to a new remote.

## 4. Garbage collection is conservative and manual

`grove wt gc` removes a worktree only when nothing can be lost: no uncommitted changes, no unpushed commits, the branch
is merged (including squash merges, detected through a merged PR whose head is the worktree's HEAD), no process has its
working directory inside it, and nothing in it changed in the last hour. It never runs on a timer; anyone can run it,
and `-n` shows what it would do. Being wrong costs someone's work, so every doubt keeps the worktree.

## 5. Local repos are first-class

`grove new <repo>` (no owner) creates a repo with no remote under `<root>/<localOwner>/<repo>`, so trying something
does not require deciding on a GitHub name or visibility up front. For these repos the worktree rules that depend on a
remote are relaxed: `new` branches from the local default branch without fetching, `ls` shows `local` instead of a count
of unpushed commits, `rm` doesn't require anything to be pushed (it keeps the branch unless it is merged, since it holds
the only copy of its commits), and `gc` uses "merged into the local default branch".
Their only copy is the local disk, which is why the generated agent instructions say so and point to `grove publish`.

## 6. `publish` moves a local repo to GitHub, all at once or not at all

`grove publish <owner>` creates the GitHub repo from the local one, pushes `main` and every `agent/*` branch that has a
worktree, moves `<repo>` and `<repo>.wt` from the local owner directory to `<owner>/`, and repairs the worktree links.
It refuses when the name is already taken on GitHub (no silent merge with an unrelated repo) and when any worktree is in
use, because moving a directory under a running process leaves it working in a path that no longer exists.

## 7. `new` creates on GitHub and refuses existing repos

`grove new <owner>/<repo>` is for repos that don't exist yet. If one does exist, it stops and suggests `grove clone`
instead of cloning it, because seeding an existing repo with an init commit would be wrong and silently cloning would
hide a typo. New GitHub repos are private unless `--public` (configurable through `GROVE_DEFAULT_VISIBILITY`): making
something public by accident is not reversible, the opposite mistake is. The initial commit, `chore: init` on `main`, is
the only direct push to `main` grove ever makes.

## 8. Every new repo gets an `AGENTS.md` skeleton without a secrets section

The skeleton asks for what an agent needs first: what the project is, how to run it and how to test it. Where secrets
come from depends on each machine, so it is not part of the per-repo template: the module documents it once, for all
repos, through `secrets.command` and `secrets.paths`.

## 9. A plain bash script configured through `GROVE_*` variables

grove is one bash script with no dependencies beyond git, gh and coreutils, so it runs anywhere, with or without Nix.
All configuration comes from environment variables (`GROVE_ROOT`, `GROVE_LOCAL_OWNER`, `GROVE_DEFAULT_VISIBILITY`,
`GROVE_TEMPLATES`); the Nix package only sets them. Templates are optional and have no default, because they are
specific to whoever uses grove; `-t` without `GROVE_TEMPLATES` is an error rather than a guess.

## 10. One generated instructions file for every repo under the root

The home-manager module writes the shared rules once, at `<root>/AGENTS.md` and `<root>/CLAUDE.md`, which agents read
because they look in parent directories. Both files carry the full text: an `@AGENTS.md` import that points outside the
project asks for approval and is ignored in non-interactive runs. Machine-specific rules go in `extraAgentsDoc`, which is
appended and never replaces the generic text, so the rules grove relies on are always present. The text names the
person in charge (`userName`) instead of "the user", so an agent knows who decides on PRs and merges.

## 11. The secrets section knows only a command and a map

The module renders `<command> <path> -- <cmd>` and a repo → paths table, and nothing else: no backend name, no login,
no project IDs. Any secrets tool with that calling convention fits, and the map lives in the config that defines it, so
there is one place to add a missing path.

## 12. Tests never touch GitHub

The tests run against a temporary `GROVE_ROOT` with local repos and local bare remotes only. The commands that talk to
GitHub (`clone`, `new <owner>/<repo>`, `publish`, squash-merge detection) run against a stub `gh` placed first on the
`PATH`, which answers from local bare repos. A test run needs no network and no credentials, and can never create,
change or read a real repository.
