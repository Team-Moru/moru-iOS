#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-Moru/Moru}"

if [[ ! -d "$ROOT" ]]; then
  echo "error: SwiftData boundary root does not exist: $ROOT" >&2
  exit 2
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required for SwiftData boundary checks." >&2
  exit 2
fi

scan_status=0
matches="$(
  rg -n '(^import SwiftData\b|\bModelContext\b|@Query\b|\bPersisted[A-Za-z0-9_]*\b)' \
    "$ROOT" --glob '*.swift'
)" || scan_status=$?

case "$scan_status" in
  0 | 1)
    ;;
  *)
    echo "error: SwiftData boundary scan failed with status $scan_status." >&2
    exit "$scan_status"
    ;;
esac

violations=""
while IFS= read -r match; do
  [[ -z "$match" ]] && continue
  case "$match" in
    */Data/Local/* | */Data/Persistence/*)
      continue
      ;;
    */App/AppLaunchCoordinator.swift:* | */App/DependencyContainer.swift:*)
      continue
      ;;
  esac
  violations+="${violations:+$'\n'}$match"
done <<< "$matches"

if [[ -n "$violations" ]]; then
  echo "SwiftData/Persisted access must stay behind repositories and app launch." >&2
  echo "$violations" >&2
  exit 1
fi

echo "SwiftData boundary check passed."
