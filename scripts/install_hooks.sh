#!/usr/bin/env bash
# Install the git hooks from this repository.
set -euo pipefail

git config core.hooksPath .githooks
echo "Git hooks installed (core.hooksPath=.githooks)."
echo "The pre-commit hook blocks commits containing Tailscale auth keys (tskey-...)."