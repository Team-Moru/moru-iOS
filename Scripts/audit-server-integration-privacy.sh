#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT="${1:-.}"
cd "$REPOSITORY_ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required for the server integration privacy audit." >&2
  exit 2
fi

failures=0

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_match() {
  local pattern="$1"
  local path="$2"
  local label="$3"

  if rg -q --multiline --pcre2 -- "$pattern" "$path"; then
    pass "$label"
  else
    fail "$label"
  fi
}

forbid_match() {
  local pattern="$1"
  local label="$2"
  shift 2

  local result_file
  result_file="$(mktemp)"

  local status
  set +e
  rg \
    -n \
    --hidden \
    --multiline \
    --pcre2 \
    -- "$pattern" "$@" >"$result_file" 2>&1
  status=$?
  set -e

  if ((status == 0)); then
    fail "$label"
    sed -n '1,40p' "$result_file" >&2
  elif ((status == 1)); then
    pass "$label"
  else
    fail "$label (audit command failed with status $status)"
    sed -n '1,40p' "$result_file" >&2
  fi

  rm -f "$result_file"
}

SOURCE_SCOPES=(
  "Moru/Moru"
  "Moru/MoruTests"
  "Scripts"
  ".github"
)

forbid_match \
  '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|sk-(?:proj-)?[A-Za-z0-9_-]{20,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' \
  "source, tests, scripts, and workflows contain no private-key or live-token signature" \
  "${SOURCE_SCOPES[@]}"

forbid_match \
  '(?i)Bearer[[:space:]]+[A-Za-z0-9._~-]{20,}' \
  "production source, scripts, and workflows contain no long bearer-token literal" \
  "Moru/Moru" "Scripts" ".github"

forbid_match \
  '(?i)Bearer[[:space:]]+(?!(?:sample|test|valid|old|new|expired|refreshed)-)[A-Za-z0-9._~-]{20,}' \
  "tests contain no non-synthetic long bearer-token literal" \
  "Moru/MoruTests"

forbid_match \
  '(?i)(logger\.(?:debug|info|notice|error|fault)|os_log|print|debugPrint|dump)\s*\([^\r\n]*(?:accessToken|refreshToken|identityToken|authorizationCode|authorizationHeader|userInput|transcript|httpBody|request\.body|response\.data)' \
  "logging calls do not interpolate tokens, authorization payloads, user input, transcripts, or bodies" \
  "Moru/Moru" "Moru/MoruTests"

forbid_match \
  '(?i)(request\.(?:headers|httpBody)|response\.data|target\.task)' \
  "network logger does not inspect headers, bodies, response bytes, or encoded tasks" \
  "Moru/Moru/Network/Core/NetworkLogPlugin.swift"

forbid_match \
  '(?i)"identity"[[:space:]]*:[[:space:]]*"(firebase|crashlytics|mixpanel|amplitude|sentry|adjust|appsflyer|facebook|admob)"|repositoryURL[^\r\n]*(firebase|crashlytics|mixpanel|amplitude|sentry|adjust|appsflyer|facebook|admob)' \
  "resolved dependencies contain no analytics, advertising, or crash-reporting SDK" \
  "Moru/Moru.xcodeproj/project.pbxproj" \
  "Moru/Moru.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

require_match \
  'request\.requestedScopes[[:space:]]*=[[:space:]]*\[[[:space:]]*\]' \
  "Moru/Moru/Features/Profile/AppleLoginReadiness.swift" \
  "Sign in with Apple requests neither name nor email scope"

forbid_match \
  'requestedScopes[[:space:]]*=[[:space:]]*\[[^\]]*\.(?:email|fullName)' \
  "production Apple login does not request email or full-name scope" \
  "Moru/Moru"

require_match \
  'kSecAttrAccessible:[[:space:]]*kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' \
  "Moru/Moru/Data/Secure/KeychainCredentialStore.swift" \
  "credentials use AfterFirstUnlockThisDeviceOnly"

require_match \
  'kSecAttrSynchronizable:[[:space:]]*kCFBooleanFalse' \
  "Moru/Moru/Data/Secure/KeychainCredentialStore.swift" \
  "credentials are not synchronizable through iCloud Keychain"

require_match \
  'RoutineGroupAiGenerateRequestDTO\(userInput:[[:space:]]*<redacted>\)' \
  "Moru/Moru/Data/Remote/RoutineSuggestion/RoutineSuggestionDTO.swift" \
  "AI request descriptions redact userInput"

require_match \
  'refreshToken:[[:space:]]*<redacted>' \
  "Moru/Moru/App/AccountSessionStore.swift" \
  "account lifecycle descriptions redact refresh tokens"

require_match \
  'accessToken:[[:space:]]*<redacted>' \
  "Moru/Moru/Data/Secure/CredentialStore.swift" \
  "persisted credential descriptions redact access tokens"

require_match \
  'maximumUserInputLength[[:space:]]*=[[:space:]]*200' \
  "Moru/Moru/Domain/Services/ServerRoutineSuggestionService.swift" \
  "AI server input remains bounded to 200 characters"

server_input_body="$(
  sed -n \
    '/static func serverInput/,/^  }/p' \
    Moru/Moru/Domain/Services/ServerRoutineSuggestionService.swift
)"

for expected_field in goalTags selectedKeywords freeformText; do
  if printf '%s\n' "$server_input_body" | rg -q -- "\.${expected_field}"; then
    pass "AI server input includes ${expected_field}"
  else
    fail "AI server input includes ${expected_field}"
  fi
done

if printf '%s\n' "$server_input_body" \
  | rg -q -- 'wakeUpHour|wakeUpMinute|weekdays|routineName|alarm|voice|transcript'; then
  fail "AI server input excludes time, weekdays, routine name, alarm, voice, and transcript"
else
  pass "AI server input excludes time, weekdays, routine name, alarm, voice, and transcript"
fi

if printf '%s\n' "$server_input_body" \
  | rg -q --multiline -- 'prefix[[:space:]]*\([^)]*maximumUserInputLength'; then
  pass "AI server input applies the declared length limit"
else
  fail "AI server input applies the declared length limit"
fi

forbid_match \
  '(?i)transcript|inputText|latitude|longitude|weather|healthKit|alarmSchedule|RoutineRun' \
  "account, voice, and AI remote contracts contain no transcript, run, location, weather, health, or alarm field" \
  "Moru/Moru/Data/Remote/Auth" \
  "Moru/Moru/Data/Remote/Voice" \
  "Moru/Moru/Data/Remote/RoutineSuggestion"

if rg \
  -n \
  'HealthTarget' \
  Moru/Moru \
  --glob '*.swift' \
  --glob '!**/Network/Targets/HealthTarget.swift' >/dev/null; then
  fail "health status target is not called by production runtime"
else
  pass "health status target is not called by production runtime"
fi

if python3 - \
  "Moru/Moru/Data/Remote/Auth/AuthDTO.swift" \
  "Moru/Moru/Data/Remote/RoutineSuggestion/RoutineSuggestionDTO.swift" \
  "Moru/Moru/Data/Remote/Voice/VoiceDTO.swift" \
  "Moru/Moru/PrivacyInfo.xcprivacy" <<'PY'
import pathlib
import plistlib
import re
import sys

auth_path, suggestion_path, voice_path, manifest_path = map(
    pathlib.Path,
    sys.argv[1:],
)


def stored_fields(path: pathlib.Path, type_name: str) -> list[str]:
    source = path.read_text(encoding="utf-8")
    match = re.search(
        rf"(?ms)^nonisolated struct {re.escape(type_name)}\b.*?^\}}\s*$",
        source,
    )
    if not match:
        raise ValueError(f"could not inspect {type_name} in {path}")
    return re.findall(
        r"(?m)^\s+let\s+([A-Za-z_][A-Za-z0-9_]*)\s*:",
        match.group(0),
    )


expected_request_fields = [
    (auth_path, "SocialLoginRequestDTO", ["token", "authorizationCode"]),
    (auth_path, "LogoutRequestDTO", ["refreshToken"]),
    (suggestion_path, "RoutineGroupAiGenerateRequestDTO", ["userInput"]),
    (voice_path, "TtsUpdateRequestDTO", ["ttsId"]),
]
for path, type_name, expected in expected_request_fields:
    actual = stored_fields(path, type_name)
    if actual != expected:
        raise ValueError(
            f"{type_name} request fields changed; expected {expected}, found {actual}"
        )

with manifest_path.open("rb") as file:
    manifest = plistlib.load(file)

if manifest.get("NSPrivacyTracking") is not False:
    raise ValueError("NSPrivacyTracking must be false")
if manifest.get("NSPrivacyTrackingDomains") != []:
    raise ValueError("NSPrivacyTrackingDomains must be empty")

expected_collected_data = {
    "NSPrivacyCollectedDataTypeUserID": {
        "linked": True,
        "purposes": ["NSPrivacyCollectedDataTypePurposeAppFunctionality"],
    },
    "NSPrivacyCollectedDataTypeOtherUserContent": {
        "linked": True,
        "purposes": [
            "NSPrivacyCollectedDataTypePurposeAppFunctionality",
            "NSPrivacyCollectedDataTypePurposeProductPersonalization",
        ],
    },
    "NSPrivacyCollectedDataTypeProductInteraction": {
        "linked": True,
        "purposes": [
            "NSPrivacyCollectedDataTypePurposeAppFunctionality",
            "NSPrivacyCollectedDataTypePurposeProductPersonalization",
        ],
    },
}

actual_collected_data = {}
for entry in manifest.get("NSPrivacyCollectedDataTypes", []):
    data_type = entry.get("NSPrivacyCollectedDataType")
    if not data_type or data_type in actual_collected_data:
        raise ValueError(f"invalid or duplicate collected-data entry: {data_type!r}")
    actual_collected_data[data_type] = {
        "linked": entry.get("NSPrivacyCollectedDataTypeLinked"),
        "tracking": entry.get("NSPrivacyCollectedDataTypeTracking"),
        "purposes": entry.get("NSPrivacyCollectedDataTypePurposes"),
    }

expected_with_tracking = {
    key: {**value, "tracking": False}
    for key, value in expected_collected_data.items()
}
if actual_collected_data != expected_with_tracking:
    raise ValueError(
        "privacy collected-data declarations changed; "
        f"expected {expected_with_tracking}, found {actual_collected_data}"
    )

expected_accessed_apis = {
    "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
}
actual_accessed_apis = {}
for entry in manifest.get("NSPrivacyAccessedAPITypes", []):
    api_type = entry.get("NSPrivacyAccessedAPIType")
    if not api_type or api_type in actual_accessed_apis:
        raise ValueError(f"invalid or duplicate accessed-API entry: {api_type!r}")
    actual_accessed_apis[api_type] = entry.get("NSPrivacyAccessedAPITypeReasons")

if actual_accessed_apis != expected_accessed_apis:
    raise ValueError(
        "privacy accessed-API declarations changed; "
        f"expected {expected_accessed_apis}, found {actual_accessed_apis}"
    )
PY
then
  pass "request DTO allowlists and privacy manifest match the reviewed P6-P8 data scope"
else
  fail "request DTO allowlists and privacy manifest match the reviewed P6-P8 data scope"
fi

if ((failures > 0)); then
  printf '\nServer integration privacy audit failed with %d finding(s).\n' \
    "$failures" >&2
  exit 1
fi

printf '\nServer integration privacy audit passed.\n'
