#!/usr/bin/env bash
# Git homework demo driver - 24bcs10112 Bibek Jyoti Charah
#
# Task 1: `git commit -m` vs `git commit -a -m` (and what -a still does NOT pick up).
# Task 2: cherry-pick a single middle commit across branches, plus a conflict + resolve + abort,
#         plus the duplicate-commit trap when you later merge the branch you cherry-picked from.
#
# Re-runnable from scratch: it wipes and recreates $WORK on every run.
# Commit identity and commit dates are pinned below, so the SHAs printed in README.md
# are reproducible byte-for-byte on a re-run (same content + same author/committer + same dates
# => same object hashes).
#
# Usage: ./git-demo.sh [workdir]        (default workdir: ./gitdemo-work)
# Transcript: ./git-demo.sh 2>&1 | tee transcript.txt

WORK="${1:-$PWD/gitdemo-work}"

# Deterministic identity, passed per-repo via `git config --local` so this demo never
# reads or writes the machine's global git config.
NAME="Bibek Jyoti Charah"
EMAIL="bibekcharah@gmail.com"

export GIT_PAGER=cat        # no `less` in a piped transcript
export GIT_EDITOR=true      # `cherry-pick --continue` must not open an editor
export LC_ALL=C

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

# run <shell command string>: echo it, run it, print its combined output and exit code.
# eval so that redirects/heredocs in the command string behave exactly as typed.
run() {
  echo "\$ $1"
  eval "$1" >"$OUT" 2>&1
  local rc=$?
  cat "$OUT"
  echo "[exit code: $rc]"
  echo
}

# Fixed clock. Bump the minute before each commit so ordering is unambiguous.
CLOCK=0
tick() {
  CLOCK=$((CLOCK + 1))
  export GIT_AUTHOR_DATE="2026-09-02T10:$(printf '%02d' "$CLOCK"):00+0530"
  export GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
}

section() {
  echo
  echo "================================================================"
  echo "$1"
  echo "================================================================"
  echo
}

init_repo() {
  rm -rf "$1"
  mkdir -p "$1"
  cd "$1" || exit 1
  git init -q -b main .
  git config --local user.name "$NAME"
  git config --local user.email "$EMAIL"
  git config --local commit.gpgsign false
}

rm -rf "$WORK"
mkdir -p "$WORK"

echo "git-demo.sh  |  $(git --version)  |  workdir: $WORK"

# ---------------------------------------------------------------------------
section "TASK 1: git commit -m  vs  git commit -a -m"
# ---------------------------------------------------------------------------

init_repo "$WORK/task1"

tick
run "echo 'line 1: original' > tracked.txt"
run "git add tracked.txt"
run "git commit -m 'c0: add tracked.txt'"

echo "--- Now produce the two kinds of change that behave differently ---"
echo
run "echo 'line 2: modification, deliberately NOT staged' >> tracked.txt"
run "printf 'this file has never been added to the index\n' > untracked.txt"

run "git status"
run "git status --short"
echo "# '  M tracked.txt' = modified in worktree, NOT in the index (second column)."
echo "# '?? untracked.txt' = git has never seen this path."
echo

echo "--- 1a. plain 'git commit -m' with an empty index ---"
echo
run "git commit -m 'attempt: plain commit -m'"
echo "# Non-zero exit, nothing committed. The index is empty, so there is nothing to record."
echo
run "git log --oneline"

echo "--- 1b. 'git commit -a -m' ---"
echo
tick
run "git commit -a -m 'c1: commit -a sweeps the tracked modification'"
run "git log --oneline"
run "git show --stat HEAD"

echo "--- 1c. proof that -a did NOT commit the untracked file ---"
echo
run "git show --stat --name-only HEAD"
run "git status --short"
echo "# untracked.txt is still '??' after the -a commit: -a means"
echo "# 'stage modifications and deletions of files git already tracks', not 'git add -A'."
echo
run "git ls-files"
run "git cat-file -p HEAD^{tree}"
echo "# The committed tree lists only tracked.txt. untracked.txt is absent from the object store."
echo

echo "--- 1d. the only way to get it in: an explicit add ---"
echo
tick
run "git add untracked.txt"
run "git commit -m 'c2: add untracked.txt explicitly'"
run "git show --stat HEAD"
run "git status --short"
run "git log --oneline"

# ---------------------------------------------------------------------------
section "TASK 2: cherry-pick"
# ---------------------------------------------------------------------------

init_repo "$WORK/task2"

echo "--- 2a. three commits on main ---"
echo
tick
run "echo 'alpha' > a.txt && git add a.txt && git commit -m 'main-1: add a.txt'"
tick
run "echo 'beta' > b.txt && git add b.txt && git commit -m 'main-2: add b.txt'"
tick
run "printf 'version: base\n' > shared.txt && git add shared.txt && git commit -m 'main-3: add shared.txt'"
run "git log --oneline"

echo "--- 2b. branch 'feature' off main, three commits on it ---"
echo
run "git switch -c feature"
tick
run "echo 'feature one' > feat1.txt && git add feat1.txt && git commit -m 'feat-1: add feat1.txt'"
tick
run "echo 'feature two - THIS is the commit we will cherry-pick' > feat2.txt && git add feat2.txt && git commit -m 'feat-2: add feat2.txt'"
tick
run "printf 'version: feature-edit\n' > shared.txt && git add shared.txt && git commit -m 'feat-3: edit shared.txt on feature'"
run "git log --oneline"
run "git log --oneline main..feature"

echo "--- 2c. identify the middle commit (feat-2) and cherry-pick ONLY it onto main ---"
echo
run "git rev-parse feature~1"
PICK=$(git rev-parse feature~1)
run "git show --stat $PICK"
run "git switch main"
run "git log --oneline"
tick
run "git cherry-pick $PICK"

echo "--- 2d. verify: new SHA, same diff ---"
echo
run "git log --oneline main"
NEWSHA=$(git rev-parse HEAD)
echo "original SHA on feature : $PICK"
echo "new SHA on main         : $NEWSHA"
echo
run "git show --stat $NEWSHA"
run "cat feat2.txt"
run "ls"
run "cat shared.txt"
echo "# feat1.txt never arrived, and shared.txt is still 'version: base' - feat-3's edit"
echo "# did not come along either. Only the one picked commit was applied."
echo
run "git log --graph --oneline --all"
echo "# Two distinct nodes carry the identical change: $PICK on feature, $NEWSHA on main."
echo
run "git diff $PICK^ $PICK"
run "git diff $NEWSHA^ $NEWSHA"
echo "# Identical patch text, different commit objects. cherry-pick copies a diff; it does not move a commit."
echo
run "git show -s --format='%H%n  parent : %P%n  author : %an <%ae> %ad%n  subject: %s' $PICK"
run "git show -s --format='%H%n  parent : %P%n  author : %an <%ae> %ad%n  subject: %s' $NEWSHA"
echo "# Note: author identity/date are preserved, the committer and parent are new."
echo

echo "--- 2e. cherry-pick conflict ---"
echo
echo "# main and feature both edited shared.txt on the same line, from the same base."
tick
run "printf 'version: main-edit\n' > shared.txt && git add shared.txt && git commit -m 'main-4: edit shared.txt on main'"
run "git log --oneline -3"
run "git rev-parse feature"
CONFLICT=$(git rev-parse feature)
run "git cherry-pick $CONFLICT"
echo "# Non-zero exit. The cherry-pick is paused, not finished."
echo
run "git status"
run "cat shared.txt"
run "git diff --name-only --diff-filter=U"

echo "--- 2f. option A: abort, throw the whole thing away ---"
echo
run "git cherry-pick --abort"
run "git status --short"
run "cat shared.txt"
run "git log --oneline -1"
echo "# Back exactly where we started: HEAD is main-4, worktree clean."
echo

echo "--- 2g. option B: resolve, then --continue ---"
echo
run "git cherry-pick $CONFLICT"
run "cat shared.txt"
echo "# Resolve by hand (keep both, which is a real decision, not a mechanical one):"
run "printf 'version: main-edit + feature-edit (resolved by hand)\n' > shared.txt"
run "git add shared.txt"
run "git status --short"
tick
run "git cherry-pick --continue --no-edit"
run "git log --oneline -3"
run "cat shared.txt"
run "git show --stat HEAD"
echo "# The resolved cherry-pick landed as yet another new SHA."
echo

echo "--- 2h. the trap: cherry-pick then merge the same branch ---"
echo
run "git log --oneline --all --graph"
run "git merge feature -m 'merge feature into main'"
echo "# Merging feature now replays feat-3 again. Its content already arrived via the"
echo "# cherry-pick, but with a DIFFERENT resolution, so git cannot fast-path it -> conflict."
echo
run "git status --short"
run "cat shared.txt"
run "git merge --abort"
run "git status --short"
run "git log --oneline -1"

echo "--- 2i. git cherry: which feature commits are already upstream by patch-id ---"
echo
run "git cherry -v main feature"
echo "# '-' = an equivalent patch already exists on main (the cherry-picked ones)."
echo "# '+' = not yet on main."
echo

section "DONE"
run "git -C '$WORK/task1' log --oneline"
run "git -C '$WORK/task2' log --oneline --graph --all"
echo "workdir left in place for inspection: $WORK"
