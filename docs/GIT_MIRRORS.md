# Keeping GitHub and Gitea in sync

The repository has two remotes:

- `origin`: GitHub (`escapechen/TixisBirdview`)
- `gitea`: the internal Gitea mirror

## Normal work

Commit once on `main`, then push the same commit to both remotes:

```sh
git status
git push origin main
git push gitea main
```

You can verify that they match:

```sh
git fetch --all --prune
git rev-parse origin/main gitea/main
```

The two hashes should be identical. If they are not, inspect the difference
before pushing or merging:

```sh
git log --left-right --graph --oneline origin/main...gitea/main
```

## After the GitHub repository rename

Rename the repository in GitHub first, then point this local clone to its new
address before the next push:

```sh
git remote set-url origin git@github.com:escapechen/TixisBirdview.git
git remote -v
```

GitHub redirects the old web URL, but updating `origin` avoids relying on that
redirect. The Gitea mirror stays unchanged unless you rename it separately.

## Rewritten history

Rewriting commits changes their hashes. Only do it deliberately, then update
both remotes after checking the branch:

```sh
git push --force-with-lease origin main
git push --force-with-lease gitea main
```

`--force-with-lease` protects against overwriting work fetched from someone
else. Do not use plain `--force`.

## Optional convenience alias

You can create a local alias that pushes to the already configured remotes:

```sh
git config alias.push-both '!f() { git push origin "$@" && git push gitea "$@"; }; f'
git push-both main
```

This is not atomic: if the second push fails, GitHub is already updated. Fix
the problem and run `git push gitea main`; do not rewrite either branch.
