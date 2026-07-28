#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - \
  "$ROOT/Moru/Moru.xcodeproj/project.pbxproj" \
  "$ROOT/Moru/Info.plist" \
  "$ROOT/Moru/Moru/Moru.entitlements" <<'PY'
import pathlib
import plistlib
import re
import sys

project_path, plist_path, entitlements_path = map(pathlib.Path, sys.argv[1:])
project = project_path.read_text(encoding="utf-8")

expected_settings = {
    "DEVELOPMENT_TEAM": "Z7FSDLFCMK",
    "MORU_APPLE_SIGN_IN_ENABLED": "YES",
    "MORU_GOOGLE_IOS_CLIENT_ID": (
        "800384412803-r62hbcns8s3jdkjaq5failk863bl19nv.apps.googleusercontent.com"
    ),
    "MORU_GOOGLE_REVERSED_CLIENT_ID": (
        "com.googleusercontent.apps."
        "800384412803-r62hbcns8s3jdkjaq5failk863bl19nv"
    ),
    "MORU_GOOGLE_SERVER_CLIENT_ID": (
        "800384412803-it81p3lkv9q9o9cel5sa6imqk1mtrr6m.apps.googleusercontent.com"
    ),
    "MORU_KAKAO_NATIVE_APP_KEY": "35f2ceb3a41aef9369e7de6ad3406685",
    "MORU_KAKAO_URL_SCHEME": "kakao35f2ceb3a41aef9369e7de6ad3406685",
    "MORU_MAIN_URL": "https://team-moru.github.io",
    "MORU_PRIVACY_POLICY_URL": "https://team-moru.github.io/privacy",
    "MORU_SUPPORT_URL": "https://team-moru.github.io/support",
    "MORU_TERMS_OF_SERVICE_URL": "https://team-moru.github.io/terms",
}

for key, expected in expected_settings.items():
    matches = re.findall(rf"^\s*{re.escape(key)} = \"?([^\";]+)\"?;", project, re.MULTILINE)
    if matches != [expected, expected]:
        raise SystemExit(
            f"error: app Debug/Release {key} must both equal {expected!r}; found {matches}"
        )

bundle_identifiers = re.findall(
    r"^\s*PRODUCT_BUNDLE_IDENTIFIER = \"?([^\";]+)\"?;",
    project,
    re.MULTILINE,
)
expected_bundle_identifiers = [
    "com.teammoru.Moru",
    "com.teammoru.Moru",
    "com.teammoru.MoruTests",
    "com.teammoru.MoruTests",
]
if bundle_identifiers != expected_bundle_identifiers:
    raise SystemExit(
        "error: app/test Debug/Release bundle identifiers changed; "
        f"found {bundle_identifiers}"
    )

with plist_path.open("rb") as file:
    info = plistlib.load(file)

expected_info_values = {
    "MoruAppleSignInEnabled": "$(MORU_APPLE_SIGN_IN_ENABLED)",
    "MoruGoogleClientID": "$(MORU_GOOGLE_IOS_CLIENT_ID)",
    "MoruGoogleReversedClientID": "$(MORU_GOOGLE_REVERSED_CLIENT_ID)",
    "MoruGoogleServerClientID": "$(MORU_GOOGLE_SERVER_CLIENT_ID)",
    "MoruKakaoNativeAppKey": "$(MORU_KAKAO_NATIVE_APP_KEY)",
    "MoruKakaoURLScheme": "$(MORU_KAKAO_URL_SCHEME)",
    "MoruMainURL": "$(MORU_MAIN_URL)",
    "MoruPrivacyPolicyURL": "$(MORU_PRIVACY_POLICY_URL)",
    "MoruSupportURL": "$(MORU_SUPPORT_URL)",
    "MoruTermsOfServiceURL": "$(MORU_TERMS_OF_SERVICE_URL)",
}
for key, expected in expected_info_values.items():
    actual = info.get(key)
    if actual != expected:
        raise SystemExit(f"error: Info.plist {key} must equal {expected!r}; found {actual!r}")

schemes = [
    item
    for url_type in info.get("CFBundleURLTypes", [])
    for item in url_type.get("CFBundleURLSchemes", [])
]
expected_schemes = [
    "$(MORU_GOOGLE_REVERSED_CLIENT_ID)",
    "$(MORU_KAKAO_URL_SCHEME)",
]
if schemes != expected_schemes:
    raise SystemExit(
        f"error: source callback schemes must equal {expected_schemes}; found {schemes}"
    )

for forbidden_key in [
    "MoruAppleKeyID",
    "MoruApplePrivateKey",
    "MoruGoogleClientSecret",
    "MoruKakaoAdminKey",
    "MoruKakaoClientSecret",
]:
    if forbidden_key in info:
        raise SystemExit(
            "error: forbidden secret/server metadata key in Info.plist: "
            f"{forbidden_key}"
        )

with entitlements_path.open("rb") as file:
    entitlements = plistlib.load(file)

apple_sign_in = entitlements.get("com.apple.developer.applesignin")
if apple_sign_in != ["Default"]:
    raise SystemExit(
        "error: Sign in with Apple entitlement must be ['Default']; "
        f"found {apple_sign_in!r}"
    )

print("Social login release configuration check passed.")
PY
