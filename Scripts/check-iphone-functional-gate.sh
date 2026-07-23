#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

python3 - \
  "$ROOT/Moru/Moru.xcodeproj/project.pbxproj" \
  "$ROOT/Moru/Info.plist" \
  "$ROOT/Moru/Moru/MoruApp.swift" \
  "$ROOT/README.md" \
  "$ROOT/Moru/docs/iPhoneFunctionalGate.md" <<'PY'
import pathlib
import plistlib
import re
import sys

project_path, plist_path, app_path, readme_path, contract_path = map(pathlib.Path, sys.argv[1:])
project = project_path.read_text(encoding="utf-8")
app = app_path.read_text(encoding="utf-8")
readme = readme_path.read_text(encoding="utf-8")
contract = contract_path.read_text(encoding="utf-8")

device_families = re.findall(r"TARGETED_DEVICE_FAMILY = ([^;]+);", project)
if device_families != ["1", "1", "1", "1"]:
    raise SystemExit(
        "error: every app/test Debug/Release configuration must use iPhone device family 1; "
        f"found {device_families}"
    )

iphone_orientations = re.findall(
    r"INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = ([^;]+);",
    project,
)
if iphone_orientations != ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortrait"]:
    raise SystemExit(
        "error: app Debug/Release configurations must declare portrait-only iPhone orientation; "
        f"found {iphone_orientations}"
    )

if "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad" in project:
    raise SystemExit(
        "error: iPad orientation build settings must not be declared for the v1 target."
    )

with plist_path.open("rb") as file:
    info = plistlib.load(file)

orientations = info.get("UISupportedInterfaceOrientations")
if orientations != ["UIInterfaceOrientationPortrait"]:
    raise SystemExit(
        "error: Info.plist must declare only UIInterfaceOrientationPortrait; "
        f"found {orientations}"
    )

if "UISupportedInterfaceOrientations~ipad" in info:
    raise SystemExit("error: Info.plist must not declare iPad orientations for the v1 target.")

if ".preferredColorScheme(.light)" not in app:
    raise SystemExit("error: the v1 app root must stay fixed to Light appearance.")

required_readme_contracts = [
    "iOS 26+ iPhone 세로 화면, 한국어, Light UI",
    "AlarmRing",
    "네 종류의 번들 MP3",
    "3초 침묵",
    "iPad, 가로 화면,",
    "Dark 디자인은 후속 범위",
]
missing_readme = [value for value in required_readme_contracts if value not in readme]
if missing_readme:
    raise SystemExit(f"error: README is missing v1 functional contracts: {missing_readme}")

required_gate_contracts = [
    "정상 AlarmKit",
    "UserNotifications fallback",
    "네 종류의 번들 MP3",
    "STT 침묵 자동 종료 기준은 3초",
    "실제 iPhone에서",
    "통과로 기록하지 않",
]
missing_gate = [value for value in required_gate_contracts if value not in contract]
if missing_gate:
    raise SystemExit(f"error: functional gate document is missing contracts: {missing_gate}")

print("iPhone portrait functional gate check passed.")
PY
