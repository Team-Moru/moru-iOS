#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-Moru/Moru}"

allowed=(
  App
  Assets.xcassets
  Data
  DesignSystem
  Domain
  Features
  Network
  Platform
  Resources
  RoutineFlow
)

is_allowed() {
  local name="$1"
  for entry in "${allowed[@]}"; do
    if [[ "$entry" == "$name" ]]; then
      return 0
    fi
  done
  return 1
}

violations=()
while IFS= read -r -d '' dir; do
  name="$(basename "$dir")"
  if ! is_allowed "$name"; then
    violations+=("$dir")
  fi
done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -print0)

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "README.md 폴더 컨벤션에 없는 top-level 디렉토리가 발견됐습니다:" >&2
  printf '  %s\n' "${violations[@]}" >&2
  echo "새 top-level 디렉토리가 정말 필요하면 README.md의 '🗂️ 폴더 컨벤션' 섹션도 함께 갱신하세요." >&2
  exit 1
fi

echo "Folder convention check passed."
