# Git / GitHub Homework

Bibek Jyoti Charah — 24bcs10112

`git-demo.sh` builds both demo repos from scratch and prints every command with its real output; the full
run is in `transcript.txt` and every block below is copied out of it verbatim. It pins the commit identity
and dates, so the SHAs quoted here repeat exactly on a re-run (`./git-demo.sh ~/.cache/gitdemo | tee
transcript.txt`, git 2.55.0).

## Task 1 — `git commit -a -m`

One commit exists (`c0` adds `tracked.txt`). I then made the two kinds of change that behave differently:
`tracked.txt` modified in the worktree but never staged, and `untracked.txt` created but never `git add`-ed.

```
$ echo 'line 2: modification, deliberately NOT staged' >> tracked.txt
$ printf 'this file has never been added to the index\n' > untracked.txt
$ git status --short
 M tracked.txt
?? untracked.txt
```

Plain `git commit -m` committed nothing and exited 1:

```
$ git commit -m 'attempt: plain commit -m'
On branch main
Changes not staged for commit:
	modified:   tracked.txt

no changes added to commit (use "git add" and/or "git commit -a")
[exit code: 1]
$ git log --oneline
734f4f3 c0: add tracked.txt
```

`git commit -a -m` staged the tracked modification and committed it in one step:

```
$ git commit -a -m 'c1: commit -a sweeps the tracked modification'
[main 7cd6cc0] c1: commit -a sweeps the tracked modification
 1 file changed, 1 insertion(+)
```

`untracked.txt` stayed out of it. The status still reports it as untracked after the commit, the index does
not list it, and only an explicit `git add` gets it in:

```
$ git status --short
?? untracked.txt
$ git ls-files
tracked.txt
$ git add untracked.txt
$ git commit -m 'c2: add untracked.txt explicitly'
[main dbf9a1c] c2: add untracked.txt explicitly
 1 file changed, 1 insertion(+)
 create mode 100644 untracked.txt
```

`git commit` records the index, and `-m` only supplies the message. `-a` widens the input to every file git
already tracks — it is `git add -u` plus a commit, so it reaches modifications and deletions of tracked
files but never a new path.

| Command | Tracked modifications | Tracked deletions | New/untracked files |
|---|---|---|---|
| `git commit -m` | no | no | no |
| `git commit -a -m` | yes | yes | no |
| `git add -A && git commit -m` | yes | yes | yes |

## Task 2 — Git cherry-pick

Three commits on `main`, then a `feature` branch with three more:

```
$ git log --oneline
2130a07 main-3: add shared.txt
6669940 main-2: add b.txt
624c6ef main-1: add a.txt
$ git switch -c feature
Switched to a new branch 'feature'
$ git log --oneline main..feature
1514135 feat-3: edit shared.txt on feature
8990bd1 feat-2: add feat2.txt
6e5b0b8 feat-1: add feat1.txt
```

The commit to move is the middle one, `feat-2`:

```
$ git rev-parse feature~1
8990bd12eb37289a786b7d3e4561af9a00445c49
$ git switch main
Switched to branch 'main'
$ git cherry-pick 8990bd12eb37289a786b7d3e4561af9a00445c49
[main ff20813] feat-2: add feat2.txt
 Date: Wed Sep 2 10:08:00 2026 +0530
 1 file changed, 1 insertion(+)
 create mode 100644 feat2.txt
```

The change is on `main` under a new SHA, and nothing else came with it — `feat1.txt` is absent and
`shared.txt` is still `version: base`, so `feat-1` and `feat-3` did not follow:

```
$ git log --oneline main
ff20813 feat-2: add feat2.txt
2130a07 main-3: add shared.txt
6669940 main-2: add b.txt
624c6ef main-1: add a.txt
original SHA on feature : 8990bd12eb37289a786b7d3e4561af9a00445c49
new SHA on main         : ff208135f6bbe35dc7202eb5b0675b87979860e7
$ cat feat2.txt
feature two - THIS is the commit we will cherry-pick
$ ls
a.txt
b.txt
feat2.txt
shared.txt
$ cat shared.txt
version: base
```

`git cherry-pick <sha>` takes the diff of that commit against its parent, applies it to the current `HEAD`
through the three-way merge machinery, and writes a new commit object; the original stays untouched on its
own branch. The author name and date are carried over, but the parent and the committer are new, and since
both go into the hash the copy gets a different SHA. Use it when you want one specific commit and not the
branch — a hotfix that has to reach a release branch, or a commit made on the wrong branch — whereas `merge`
brings the whole branch across with its history intact and `rebase` replays your entire branch onto a new base.

### Conflict during a cherry-pick

`main` and `feature` both edited the same line of `shared.txt` from the same base commit, so picking `feat-3`
onto `main` conflicts. Git pauses the cherry-pick rather than rolling it back, leaving `--abort`, `--skip` or
resolve-and-`--continue` as the ways out.

```
$ printf 'version: main-edit\n' > shared.txt && git add shared.txt && git commit -m 'main-4: edit shared.txt on main'
[main 2760b20] main-4: edit shared.txt on main
 1 file changed, 1 insertion(+), 1 deletion(-)
$ git cherry-pick 15141353b78b0266822623470631aa3eb0fb7833
Auto-merging shared.txt
CONFLICT (content): Merge conflict in shared.txt
error: could not apply 1514135... feat-3: edit shared.txt on feature
hint: After resolving the conflicts, mark them with
hint: "git add/rm <pathspec>", then run
hint: "git cherry-pick --continue".
[exit code: 1]
$ cat shared.txt
<<<<<<< HEAD
version: main-edit
=======
version: feature-edit
>>>>>>> 1514135 (feat-3: edit shared.txt on feature)
$ printf 'version: main-edit + feature-edit (resolved by hand)\n' > shared.txt
$ git add shared.txt
$ git cherry-pick --continue --no-edit
[main d491933] feat-3: edit shared.txt on feature
 Date: Wed Sep 2 10:09:00 2026 +0530
 1 file changed, 1 insertion(+), 1 deletion(-)
$ git log --oneline -3
d491933 feat-3: edit shared.txt on feature
2760b20 main-4: edit shared.txt on main
ff20813 feat-2: add feat2.txt
$ cat shared.txt
version: main-edit + feature-edit (resolved by hand)
```

`git add` on the conflicted path is what marks it resolved, and `--continue` then writes the commit.
