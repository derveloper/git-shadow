# git-shadow

Automatic shadow backups for local git repositories.

Every `git init` creates a bare mirror repo outside your project directory. Hooks push every commit there in the background. Delete your project by accident? Clone it back from the shadow.

Built for the age of AI coding assistants that occasionally `rm -rf` things they shouldn't.

## How it works

```
~/projects/rest-api/          ~/.git-shadows/
  .git/                         rest-api-shadow.git   <-- bare backup
    hooks/
      post-commit  ----push---->
      post-merge   ----push---->
      post-rewrite ----push---->
  src/
  ...
```

Hooks run `git push` in the background after every commit, merge, and rewrite (amend/rebase). Non-blocking, silent, no manual steps.

## Install

```
curl -fsSL https://raw.githubusercontent.com/derveloper/git-shadow/main/install.sh | bash
```

Or manually: copy `git-shadow` somewhere on your `PATH`.

## Usage

**New repo:**

```
git shadow init
```

**Existing repo** (works with or without a remote):

```
cd my-project
git shadow enable
```

**That's it.** Every commit is now backed up automatically.

### Other commands

```bash
git shadow status     # show shadow state for current repo
git shadow list       # show all shadow repos
git shadow disable    # remove hooks and remote (shadow repo stays)
```

### Transparent git init wrapping

Add to `.zshrc` / `.bashrc` so every `git init` gets a shadow automatically:

```bash
eval "$(git shadow shell-init)"
```

## Recovery

```bash
# oops
rm -rf my-project

# no problem
git clone ~/.git-shadows/my-project-shadow.git my-project
```

All branches, all commits, all tags.

## What gets backed up

| Event | Hook | Backed up |
|---|---|---|
| `git commit` | post-commit | yes |
| `git merge` / `git pull` | post-merge | yes |
| `git commit --amend` | post-rewrite | yes (force push) |
| `git rebase` | post-rewrite | yes (force push) |

Pushes use `--all --force` so all branches stay in sync, including after history rewrites.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `GIT_SHADOW_DIR` | `~/.git-shadows` | Where shadow repos are stored |

## Design decisions

**Shadow lives outside the project.** Unlike `.git` backups or tools that store history inside the working tree, the shadow repo is in a separate directory tree. `rm -rf project/` can't touch it.

**One bare repo per project.** Named `<dirname>-shadow.git`. If two projects share a dirname, the second gets a hash suffix (e.g. `myapp-shadow-a1b2c3d4.git`).

**Hooks append, not replace.** If you have existing git hooks, git-shadow appends its block. Removing it with `git shadow disable` leaves your hooks intact.

**Async push.** The hook backgrounds the push (`&`) so commits feel exactly as fast as before.

**Local only.** This protects against software mistakes (accidental deletion, bad scripts, overeager AI agents). Not against disk failure. For that, use actual backups.

## Tests

```
./test.sh
```

20 tests, pure bash, no dependencies beyond git. Runs in a temp sandbox, cleans up after itself.

## License

MIT
