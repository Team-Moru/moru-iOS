#!/usr/bin/env bash
# 로컬·CI 공용 테스트 러너.
#
# 사용법:
#   bash Scripts/run-tests.sh smoke [xcodebuild 추가 인자…]   # MoruSmoke 테스트 플랜
#   bash Scripts/run-tests.sh full  [xcodebuild 추가 인자…]   # MoruFull 테스트 플랜 (+ UI 테스트)
#   bash Scripts/run-tests.sh build                          # build-for-testing 만
#
# 환경변수:
#   MORU_SIMULATOR_UDID   사용할 시뮬레이터 UDID (지정 시 자동 탐색 생략)
#   MORU_SIMULATOR_NAME   자동 탐색 시 name 필터 정규식 (기본 .*)
#   MORU_XCODEBUILD_QUIET 1이면 xcodebuild -quiet
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Moru/Moru.xcodeproj"
SCHEME="Moru"
MODE="${1:-smoke}"
shift || true

case "$MODE" in
  smoke) PLAN="MoruSmoke" ;;
  full) PLAN="MoruFull" ;;
  build) PLAN="" ;;
  *)
    echo "usage: $0 {smoke|full|build} [xcodebuild args…]" >&2
    exit 64
    ;;
esac

UDID="${MORU_SIMULATOR_UDID:-}"
if [[ -z "$UDID" ]]; then
  name_filter="${MORU_SIMULATOR_NAME:-.*}"
  UDID="$(
    xcodebuild -showdestinations -project "$PROJECT" -scheme "$SCHEME" 2>/dev/null \
      | grep 'platform:iOS Simulator' \
      | grep -v placeholder \
      | grep -E "name:${name_filter}" \
      | head -1 \
      | sed -E 's/.*id:([0-9A-Fa-f-]+).*/\1/' \
      || true
  )"
fi
if [[ -z "$UDID" ]]; then
  UDID="$(
    xcrun simctl list devices available -j \
      | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if "iPhone" in device.get("name", "") and device.get("isAvailable"):
            print(device["udid"])
            raise SystemExit(0)
'
  )"
fi
if [[ -z "$UDID" ]]; then
  echo "error: iOS Simulator destination을 찾지 못했습니다. MORU_SIMULATOR_UDID를 지정하세요." >&2
  exit 2
fi

xcrun simctl bootstatus "$UDID" -b >/dev/null
echo "simulator: $UDID"

BUILD_DIR="$ROOT/build"
mkdir -p "$BUILD_DIR/TestResults" "$BUILD_DIR/captures"
timestamp="$(date +%Y%m%d-%H%M%S)"

common_args=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -destination "platform=iOS Simulator,id=$UDID"
  -derivedDataPath "$BUILD_DIR/DerivedData"
  -clonedSourcePackagesDirPath "$BUILD_DIR/SourcePackages"
  CODE_SIGNING_ALLOWED=NO
)
if [[ "${MORU_XCODEBUILD_QUIET:-0}" == "1" ]]; then
  common_args+=(-quiet)
fi

if [[ -z "$PLAN" ]]; then
  xcodebuild build-for-testing "${common_args[@]}" "$@"
  exit 0
fi

export TEST_RUNNER_MORU_CAPTURE_OUTPUT_DIR="$BUILD_DIR/captures/$MODE"
mkdir -p "$TEST_RUNNER_MORU_CAPTURE_OUTPUT_DIR"

result_bundle="$BUILD_DIR/TestResults/$MODE-$timestamp.xcresult"
set +e
if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild test "${common_args[@]}" \
    -testPlan "$PLAN" \
    -resultBundlePath "$result_bundle" \
    "$@" | xcbeautify
  status="${PIPESTATUS[0]}"
else
  xcodebuild test "${common_args[@]}" \
    -testPlan "$PLAN" \
    -resultBundlePath "$result_bundle" \
    "$@"
  status="$?"
fi
set -e

echo "result bundle: $result_bundle"
exit "$status"
