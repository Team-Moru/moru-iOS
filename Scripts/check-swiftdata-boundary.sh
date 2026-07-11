#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-Moru/Moru}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required for SwiftData boundary checks." >&2
  exit 2
fi

violations="$(
  rg -n '(^import SwiftData\b|\bModelContext\b|@Query\b|\bPersisted[A-Za-z0-9_]*\b)' "$ROOT" --glob '*.swift' \
    | rg -v '/Data/(Local|Persistence)/' \
    | rg -v '/App/(AppBootstrapper|DependencyContainer)\.swift:' \
    || true
)"

if [[ -n "$violations" ]]; then
  echo "SwiftData/Persisted access must stay behind repositories and app bootstrap." >&2
  echo "$violations" >&2
  exit 1
fi

echo "SwiftData boundary check passed."
