# Session 5 - Git / GitHub homework

Bibek Jyoti Charah, 24bcs10112 (github: SammyUrfen)

Two tasks:

1. `git commit -a -m` vs `git commit -m`, including the part people get wrong (what `-a` still ignores).
2. `git cherry-pick` a single middle commit across branches, plus a conflict, its resolution, an abort, and the duplicate-commit trap.

## Files

| File | What it is |
|---|---|
| `git-demo.sh` | The driver. Builds both demo repos from scratch and prints every command with its real output. Re-runnable. |
| `transcript.txt` | The full captured run, 571 lines. Everything quoted in this README is copied out of it. |
| `repro-check.txt` | Two runs diffed, to show the SHAs below are reproducible and not hand-typed. |

## How this was produced

```
$ ./git-demo.sh ~/.cache/gitdemo 2>&1 | tee transcript.txt
```

Every output block below is real captured output. Nothing is retyped from memory.

The demo repos are built in a scratch directory outside this folder, so no nested `.git` ends up in the
submission. The script pins the commit identity with `git config --local` (so it does not read or depend on my
global git config) and pins `GIT_AUTHOR_DATE` / `GIT_COMMITTER_DATE` to a fixed clock. Same content + same
identity + same dates means the same object hashes, so the SHAs in this README reproduce exactly:

```
$ W=~/.cache/gitdemo
$ ./git-demo.sh "$W" > run1.txt 2>&1
$ ./git-demo.sh "$W" > run2.txt 2>&1
$ diff run1.txt run2.txt; echo "diff exit: $?"
diff exit: 0
$ sha256sum run1.txt run2.txt
154f30d312ee385f1db936882a621c81ca813f6551368c00ea4f0d899e6f772d  run1.txt
154f30d312ee385f1db936882a621c81ca813f6551368c00ea4f0d899e6f772d  run2.txt
```

Environment: git 2.55.0, Fedora, bash.

---

# Task 1: `git commit -m` vs `git commit -a -m`

## The setup

One commit exists (`c0` adds `tracked.txt`). Then I create the two kinds of change that behave differently:

- `tracked.txt` is **modified in the worktree but not staged**
- `untracked.txt` is **new and never `git add`-ed**

```
$ echo 'line 2: modification, deliberately NOT staged' >> tracked.txt
$ printf 'this file has never been added to the index\n' > untracked.txt

$ git status --short
 M tracked.txt
?? untracked.txt
```

`git status --short` uses two columns: index status, then worktree status. ` M` (leading space) means the
modification is only in the worktree; the index still holds the old version. `??` means git has no record of the
path at all.

## 1a. Plain `git commit -m` commits nothing

```
$ git commit -m 'attempt: plain commit -m'
On branch main
Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
	modified:   tracked.txt

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	untracked.txt

no changes added to commit (use "git add" and/or "git commit -a")
[exit code: 1]

$ git log --oneline
734f4f3 c0: add tracked.txt
```

Exit code 1, and the log is unchanged. `git commit` records **the index**, not the worktree. The index is
identical to `HEAD`, so there is nothing to record and git refuses rather than making an empty commit.

## 1b. `git commit -a -m` sweeps the tracked modification

```
$ git commit -a -m 'c1: commit -a sweeps the tracked modification'
[main 7cd6cc0] c1: commit -a sweeps the tracked modification
 1 file changed, 1 insertion(+)

$ git show --stat HEAD
commit 7cd6cc0e681acec1c0a7b0669efa6af6b4a9f136
Author: Bibek Jyoti Charah <bibekcharah@gmail.com>
Date:   Wed Sep 2 10:02:00 2026 +0530

    c1: commit -a sweeps the tracked modification

 tracked.txt | 1 +
 1 file changed, 1 insertion(+)
```

`-a` is a shorthand for "stage the modifications and deletions of every file git already tracks, then commit".
It is `git add -u` followed by `git commit`, not a new capability.

## 1c. The part people get wrong: `-a` did NOT commit the untracked file

This is the whole point of the task, so it is proved three ways rather than asserted.

```
$ git show --stat --name-only HEAD
commit 7cd6cc0e681acec1c0a7b0669efa6af6b4a9f136
...
    c1: commit -a sweeps the tracked modification

tracked.txt

$ git status --short
?? untracked.txt

$ git ls-files
tracked.txt

$ git cat-file -p HEAD^{tree}
100644 blob 5d024043f3afe00cd3dcb65dbc797d92377c2458	tracked.txt
```

1. `git show --name-only` lists only `tracked.txt` in the commit.
2. `git status --short` still reports `?? untracked.txt` **after** the `-a` commit.
3. `git ls-files` (the index) and the committed tree object itself both contain only `tracked.txt`. The
   untracked file has no blob in the object store at all.

`-a` operates on the **tracked set**. A file git has never seen is not in that set, so `-a` cannot reach it.
`git add -A` / `git add .` is what stages new paths; `-a` is not a substitute for it.

## 1d. The only way in is an explicit add

```
$ git add untracked.txt
$ git commit -m 'c2: add untracked.txt explicitly'
[main dbf9a1c] c2: add untracked.txt explicitly
 1 file changed, 1 insertion(+)
 create mode 100644 untracked.txt

$ git status --short
[exit code: 0]

$ git log --oneline
dbf9a1c c2: add untracked.txt explicitly
7cd6cc0 c1: commit -a sweeps the tracked modification
734f4f3 c0: add tracked.txt
```

## What I understood

| Command | Stages tracked modifications | Stages tracked deletions | Stages new/untracked files |
|---|---|---|---|
| `git commit -m` | no | no | no |
| `git commit -a -m` | yes | yes | **no** |
| `git add -A && git commit -m` | yes | yes | yes |

`git commit` always snapshots the index. `-m` only supplies the message; it changes nothing about what gets
staged. `-a` widens the input to "everything already tracked". The failure mode in practice is a developer who
uses `git commit -a -m` habitually, adds a new source file, and pushes a build that does not compile for anyone
else, because that new file only ever existed on their disk. `git status` before every push is the cheap guard.

---

# Task 2: cherry-pick

## 2a / 2b. Three commits on main, three on a feature branch

First `git log --oneline` below runs on `main`, the second runs on `feature` after the branch is created.

```
$ git log --oneline
2130a07 main-3: add shared.txt
6669940 main-2: add b.txt
624c6ef main-1: add a.txt

$ git switch -c feature
Switched to a new branch 'feature'

$ git log --oneline
1514135 feat-3: edit shared.txt on feature
8990bd1 feat-2: add feat2.txt
6e5b0b8 feat-1: add feat1.txt
2130a07 main-3: add shared.txt
6669940 main-2: add b.txt
624c6ef main-1: add a.txt

$ git log --oneline main..feature
1514135 feat-3: edit shared.txt on feature
8990bd1 feat-2: add feat2.txt
6e5b0b8 feat-1: add feat1.txt
```

`main-3` creates `shared.txt` with `version: base`. That shared file is what the conflict demo in 2e uses later.

## 2c. Pick out the middle commit and cherry-pick only it

The middle commit on `feature` is `feat-2` (`8990bd1`), addressed as `feature~1`:

```
$ git rev-parse feature~1
8990bd12eb37289a786b7d3e4561af9a00445c49

$ git show --stat 8990bd12eb37289a786b7d3e4561af9a00445c49
commit 8990bd12eb37289a786b7d3e4561af9a00445c49
Author: Bibek Jyoti Charah <bibekcharah@gmail.com>
Date:   Wed Sep 2 10:08:00 2026 +0530

    feat-2: add feat2.txt

 feat2.txt | 1 +
 1 file changed, 1 insertion(+)

$ git switch main
$ git cherry-pick 8990bd12eb37289a786b7d3e4561af9a00445c49
[main ff20813] feat-2: add feat2.txt
 Date: Wed Sep 2 10:08:00 2026 +0530
 1 file changed, 1 insertion(+)
 create mode 100644 feat2.txt
```

## 2d. Verify

```
$ git log --oneline main
ff20813 feat-2: add feat2.txt
2130a07 main-3: add shared.txt
6669940 main-2: add b.txt
624c6ef main-1: add a.txt

original SHA on feature : 8990bd12eb37289a786b7d3e4561af9a00445c49
new SHA on main         : ff208135f6bbe35dc7202eb5b0675b87979860e7

$ git show --stat ff208135f6bbe35dc7202eb5b0675b87979860e7
commit ff208135f6bbe35dc7202eb5b0675b87979860e7
Author: Bibek Jyoti Charah <bibekcharah@gmail.com>
Date:   Wed Sep 2 10:08:00 2026 +0530

    feat-2: add feat2.txt

 feat2.txt | 1 +
 1 file changed, 1 insertion(+)

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

The file content landed on main. `feat1.txt` did not come along, and `shared.txt` is still `version: base`, so
`feat-3`'s edit did not come along either. Only the one selected commit was applied.

Two distinct SHAs for the same change:

```
$ git log --graph --oneline --all
* ff20813 feat-2: add feat2.txt
| * 1514135 feat-3: edit shared.txt on feature
| * 8990bd1 feat-2: add feat2.txt
| * 6e5b0b8 feat-1: add feat1.txt
|/
* 2130a07 main-3: add shared.txt
* 6669940 main-2: add b.txt
* 624c6ef main-1: add a.txt
```

The identical patch, from two different commit objects:

```
$ git diff 8990bd12eb37289a786b7d3e4561af9a00445c49^ 8990bd12eb37289a786b7d3e4561af9a00445c49
diff --git a/feat2.txt b/feat2.txt
new file mode 100644
index 0000000..e250b82
--- /dev/null
+++ b/feat2.txt
@@ -0,0 +1 @@
+feature two - THIS is the commit we will cherry-pick

$ git diff ff208135f6bbe35dc7202eb5b0675b87979860e7^ ff208135f6bbe35dc7202eb5b0675b87979860e7
diff --git a/feat2.txt b/feat2.txt
new file mode 100644
index 0000000..e250b82
--- /dev/null
+++ b/feat2.txt
@@ -0,0 +1 @@
+feature two - THIS is the commit we will cherry-pick
```

And why the SHAs differ, since the diff does not:

```
$ git show -s --format='%H%n  parent : %P%n  author : %an <%ae> %ad%n  subject: %s' 8990bd12eb37289a786b7d3e4561af9a00445c49
8990bd12eb37289a786b7d3e4561af9a00445c49
  parent : 6e5b0b8bdd4fd8784c778ab57309c10e35ee04e3
  author : Bibek Jyoti Charah <bibekcharah@gmail.com> Wed Sep 2 10:08:00 2026 +0530
  subject: feat-2: add feat2.txt

$ git show -s --format='%H%n  parent : %P%n  author : %an <%ae> %ad%n  subject: %s' ff208135f6bbe35dc7202eb5b0675b87979860e7
ff208135f6bbe35dc7202eb5b0675b87979860e7
  parent : 2130a07da4db77181c952e51146c8b932ce69030
  author : Bibek Jyoti Charah <bibekcharah@gmail.com> Wed Sep 2 10:08:00 2026 +0530
  subject: feat-2: add feat2.txt
```

Different **parent**, and a different committer timestamp on a real (unpinned) run. A commit SHA is the hash of
the commit object, which includes the tree, the parent pointer, the author line and the committer line. Change
the parent and the hash necessarily changes.

## 2e. Cherry-pick conflict

Setup: `main` and `feature` both edit the same line of `shared.txt`, from the same base commit `main-3`.

```
$ printf 'version: main-edit\n' > shared.txt && git add shared.txt && git commit -m 'main-4: edit shared.txt on main'
[main 2760b20] main-4: edit shared.txt on main

$ git cherry-pick 15141353b78b0266822623470631aa3eb0fb7833
Auto-merging shared.txt
CONFLICT (content): Merge conflict in shared.txt
error: could not apply 1514135... feat-3: edit shared.txt on feature
hint: After resolving the conflicts, mark them with
hint: "git add/rm <pathspec>", then run
hint: "git cherry-pick --continue".
hint: You can instead skip this commit with "git cherry-pick --skip".
hint: To abort and get back to the state before "git cherry-pick",
hint: run "git cherry-pick --abort".
[exit code: 1]

$ git status
On branch main
You are currently cherry-picking commit 1514135.
  (fix conflicts and run "git cherry-pick --continue")
  (use "git cherry-pick --skip" to skip this patch)
  (use "git cherry-pick --abort" to cancel the cherry-pick operation)

Unmerged paths:
  (use "git add <file>..." to mark resolution)
	both modified:   shared.txt

$ cat shared.txt
<<<<<<< HEAD
version: main-edit
=======
version: feature-edit
>>>>>>> 1514135 (feat-3: edit shared.txt on feature)

$ git diff --name-only --diff-filter=U
shared.txt
```

The cherry-pick is **paused**, not failed-and-rolled-back. The repo is in a `CHERRY_PICK_HEAD` state and there
are exactly three ways out: `--abort`, `--skip`, or resolve + `--continue`.

## 2f. Option A: `--abort`

```
$ git cherry-pick --abort
$ git status --short
[exit code: 0]
$ cat shared.txt
version: main-edit
$ git log --oneline -1
2760b20 main-4: edit shared.txt on main
```

Back to exactly the pre-cherry-pick state: HEAD is `main-4`, worktree clean, no conflict markers left behind.

## 2g. Option B: resolve, then `--continue`

```
$ git cherry-pick 15141353b78b0266822623470631aa3eb0fb7833
CONFLICT (content): Merge conflict in shared.txt
[exit code: 1]

$ printf 'version: main-edit + feature-edit (resolved by hand)\n' > shared.txt
$ git add shared.txt
$ git status --short
M  shared.txt

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

`git add` on the conflicted path is what marks it resolved; `--continue` then writes the commit. The resolution
here keeps both edits, which is a judgement call about intent, not something git can do for you. Note that the
resolved commit `d491933` now contains a diff that is **not** the same as the original `1514135` - which is
exactly what causes 2h.

## 2h. The trap: cherry-pick, then merge the same branch

```
$ git merge feature -m 'merge feature into main'
Auto-merging shared.txt
CONFLICT (content): Merge conflict in shared.txt
Automatic merge failed; fix conflicts and then commit the result.
[exit code: 1]

$ git status --short
A  feat1.txt
UU shared.txt

$ cat shared.txt
<<<<<<< HEAD
version: main-edit + feature-edit (resolved by hand)
=======
version: feature-edit
>>>>>>> feature

$ git merge --abort
```

The merge base is still `main-3`, because the cherry-picks created new commits and did **not** make `feature` an
ancestor of `main`. So the three-way merge sees `shared.txt` changed on both sides relative to `version: base`
and has to ask. The content already arrived on main via the cherry-pick, but with a different resolution, so git
cannot recognise it as the same change.

Note `A feat1.txt` in the status: that part of the merge was clean. Cherry-picking does not stop a later merge
from working, it just makes the conflicts avoidable-in-principle but real-in-practice.

## 2i. `git cherry`, for detecting this before it bites

```
$ git cherry -v main feature
+ 6e5b0b8bdd4fd8784c778ab57309c10e35ee04e3 feat-1: add feat1.txt
- 8990bd12eb37289a786b7d3e4561af9a00445c49 feat-2: add feat2.txt
+ 15141353b78b0266822623470631aa3eb0fb7833 feat-3: edit shared.txt on feature
```

`-` means an equivalent patch already exists upstream, matched by **patch-id** (a hash of the diff, ignoring
SHA/parent/timestamp), not by SHA. `feat-2` was cherry-picked verbatim so it matches. `feat-3` was cherry-picked
**with a modified resolution**, so its patch-id no longer matches and it shows as `+`, still-to-come. That is the
same fact that makes 2h conflict, visible before you run the merge.

---

## What I understood: cherry-pick

**It is a copy, not a move.** `git cherry-pick <sha>` computes the diff of `<sha>` against its parent, applies
that diff to the current `HEAD` using the three-way merge machinery, and writes a **new commit object** with a
new SHA. The original commit stays exactly where it was; nothing on the source branch is modified. It preserves
the original author name and author date, but the committer and the parent are new, which is why the hash
differs. Applying a diff is also why it can conflict: git is merging, not replaying a filesystem snapshot.

`git cherry-pick A..B` picks a range, `-n` / `--no-commit` stages without committing, `-x` appends a
`(cherry picked from commit ...)` line to the message - worth using on long-lived release branches so the
duplicate is traceable later.

### cherry-pick vs merge vs rebase

| | What it does to history | Use when |
|---|---|---|
| `merge` | Adds a merge commit joining two lines of history. Nothing is rewritten. Both parents recorded. | You want **all** the work on a branch, and you want the true history preserved. The default for integrating a finished feature branch. |
| `rebase` | Replays **your whole branch's** commits onto a new base, creating new SHAs for all of them. Old commits become unreachable. | You want a linear history for a branch that is still private. Never on a branch others have pulled. |
| `cherry-pick` | Copies **one (or a few) specific** commits onto the current branch as new commits. | You want a subset, not the branch. Classic case: a hotfix committed on `main` that has to go into `release/1.4` without dragging along everything else on main. Or a fix landed on the wrong branch. |

Rule of thumb: cherry-pick is for **surgical** transfers of a small number of commits between branches that are
not going to be merged into each other. If the two branches will be merged later, prefer merge, because
cherry-picking first is what sets up the trap.

### The trap, stated plainly

Cherry-picking creates a **duplicate**: the same change now exists as two commits with two different SHAs. Two
consequences:

1. **A duplicated log.** After merging `feature` into `main`, `git log` shows `feat-2: add feat2.txt` twice
   (once cherry-picked, once via the merge), which makes history and `git blame` harder to read. Git deduplicates
   the *content* when it can - identical patches merge as no-ops - but the *commits* remain two.
2. **Conflicts on the later merge.** This is the sharp edge. As long as the cherry-picked patch is byte-identical,
   the merge usually resolves silently. The moment you resolve a conflict during the cherry-pick, or amend, or
   the surrounding code drifts, the two versions differ, git's merge base predates both, and you have to resolve
   the *same* change twice - as shown in 2h. Worse, a careless resolution at that second merge can revert the
   first one.

Mitigations: `git cherry -v upstream branch` to see what is already there by patch-id; `-x` so the duplicate is
labelled; and structurally, don't cherry-pick between branches you already intend to merge.

---

## Limitations

- Everything here runs against local repositories only. No GitHub remote was created, so push/pull/PR flows,
  `git push --force-with-lease` after a rebase, and the remote-side view of a duplicated commit are out of
  scope of this submission.
- The demo dates and identity are pinned, so the SHAs are reproducible. On an unpinned run the SHAs will differ
  (the committer timestamp is part of the hash) while the structure - one original commit, one new commit, same
  diff, different parent - is identical.
- `git cherry-pick --skip` is named in the transcript output (git's own hint text) but not exercised as a
  separate step; only `--abort` and `--continue` were demonstrated.
