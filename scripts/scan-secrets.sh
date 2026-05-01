#!/usr/bin/env bash
# Scan the working tree for leaked secrets using TruffleHog.
# Mirrors the GitHub Actions check at .github/workflows/SecretScan.yml so
# you can catch issues before pushing.
#
# Requires trufflehog: `brew install trufflehog`

set -euo pipefail

if ! command -v trufflehog >/dev/null 2>&1; then
    echo "trufflehog not found. Install with: brew install trufflehog" >&2
    exit 2
fi

cd "$(git rev-parse --show-toplevel)"

# By default, scan only commits since main so re-scans don't drown in
# false positives from old bundled Wine binaries that pre-date the fork.
BASE="${1:-origin/main}"

echo "Scanning commits since $BASE for verified secrets..."
trufflehog git \
    --since-commit "$BASE" \
    --branch HEAD \
    --only-verified \
    --fail \
    file://.

echo "✅ No verified secrets found."
