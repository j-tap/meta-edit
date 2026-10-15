#!/usr/bin/env bash
# Cut a release: write VERSION, commit, tag vX.Y.Z and push.
# GitHub Actions picks up the tag, builds all three apps and publishes the release.
# Usage: scripts/release.sh 1.2.0
set -euo pipefail

v="${1:-}"
if [[ ! "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 X.Y.Z" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

branch="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$branch" != "main" ]]; then
  echo "release from main only (current branch: $branch)" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is not clean" >&2
  exit 1
fi
if git rev-parse "v$v" >/dev/null 2>&1; then
  echo "tag v$v already exists" >&2
  exit 1
fi

git pull --ff-only
if [[ "$(tr -d '[:space:]' < VERSION)" != "$v" ]]; then
  echo "$v" > VERSION
  git add VERSION
  git commit -m "Release $v"
fi
git tag -a "v$v" -m "Release $v"
git push origin main "v$v"
echo "Tagged v$v. CI will build and publish the release."
