#!/bin/bash
# Dependency Update Checker — checks for newer versions of pinned packages
# Triggered by PM2 cron (see pm2/ecosystem.config.js.example)

LOG="$HOME/.local/share/logs/dep-updates-$(date +%Y-%m-%d).log"
mkdir -p "$(dirname "$LOG")"

# Replace with your notification endpoint
NTFY_URL=""  # e.g., "https://ntfy.example.com/your-topic"
UPDATES=""

# Check npm packages — add your pinned global packages here
for pkg in "@tobilu/qmd" "cui-server"; do
    CURRENT=$(npm list -g "$pkg" --depth=0 2>/dev/null | grep "$pkg" | awk -F@ '{print $NF}')
    LATEST=$(npm view "$pkg" version 2>/dev/null)
    if [ -n "$CURRENT" ] && [ -n "$LATEST" ] && [ "$CURRENT" != "$LATEST" ]; then
        UPDATES="${UPDATES}npm: ${pkg} ${CURRENT} → ${LATEST}\n"
    fi
done

# Check pip packages — add your pinned pip packages here
for pkg in "memsearch"; do
    CURRENT=$(pip show "$pkg" 2>/dev/null | grep Version | awk '{print $2}')
    LATEST=$(pip index versions "$pkg" 2>/dev/null | head -1 | grep -oP '\([\d.]+\)' | tr -d '()')
    if [ -n "$CURRENT" ] && [ -n "$LATEST" ] && [ "$CURRENT" != "$LATEST" ]; then
        UPDATES="${UPDATES}pip: ${pkg} ${CURRENT} → ${LATEST}\n"
    fi
done

# Check Docker images — add images you pin to specific versions
# Example: Authelia pinned to a major version
for img in "authelia/authelia:4.38"; do
    REPO=$(echo "$img" | cut -d: -f1)
    TAG=$(echo "$img" | cut -d: -f2)
    LATEST=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','').lstrip('v'))" 2>/dev/null)
    if [ -n "$LATEST" ] && [ "$TAG" != "$LATEST" ]; then
        UPDATES="${UPDATES}docker: ${REPO} ${TAG} → ${LATEST} (CHECK BREAKING CHANGES before updating)\n"
    fi
done

# Check Claude Code CLI
CC_CURRENT=$(claude --version 2>/dev/null | head -1 | awk '{print $1}')
CC_LATEST=$(npm view @anthropic-ai/claude-code version 2>/dev/null)
if [ -n "$CC_CURRENT" ] && [ -n "$CC_LATEST" ] && [ "$CC_CURRENT" != "$CC_LATEST" ]; then
    UPDATES="${UPDATES}npm: claude-code ${CC_CURRENT} → ${CC_LATEST}\n"
fi

if [ -n "$UPDATES" ]; then
    echo -e "$UPDATES" | tee -a "$LOG"
    [ -n "$NTFY_URL" ] && curl -s -H "Title: Dependency updates available" -d "$(echo -e "$UPDATES")" "$NTFY_URL" > /dev/null
else
    echo "All dependencies up to date" >> "$LOG"
fi

# Cleanup old logs
find "$(dirname "$LOG")" -name "dep-updates-*.log" -mtime +30 -delete
