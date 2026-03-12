#!/bin/bash
# git-snapshot.sh
# Commits any uncommitted changes in version-controlled config repos.
# Runs nightly to ensure manual edits and agent-driven changes are captured.
#
# Intended to run via system cron or PM2 cron, just before the nightly backup.
# Skips repos with no changes. Pushes to remote after each commit.

REPOS=(
    "/home/YOUR_USER/docker"
    "/home/YOUR_USER/scripts"
    "/opt/appdata"
    "/home/YOUR_USER/repos/personal/YOUR_CONTEXT_REPO"
)

DATE=$(date +%Y-%m-%d)

for REPO in "${REPOS[@]}"; do
    if [ ! -d "$REPO/.git" ]; then
        echo "[git-snapshot] WARNING: $REPO is not a git repo, skipping"
        continue
    fi

    cd "$REPO" || continue

    # Stage all tracked+untracked files (respecting .gitignore)
    git add -A

    # Only commit if there's something to commit
    if git diff --cached --quiet; then
        echo "[git-snapshot] $REPO: no changes"
    else
        git commit -m "nightly snapshot $DATE"
        echo "[git-snapshot] $REPO: committed changes"
    fi

    # Push to remote
    if git push 2>&1; then
        echo "[git-snapshot] $REPO: pushed"
    else
        echo "[git-snapshot] $REPO: push failed"
    fi
done
