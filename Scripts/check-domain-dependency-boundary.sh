#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:-Moru/Moru}"

python3 - "$SOURCE_ROOT" <<'PY'
from __future__ import annotations

import pathlib
import re
import sys


source_root = pathlib.Path(sys.argv[1])
domain_root = source_root / "Domain"
outward_roots = [
    source_root / "App",
    source_root / "Data",
    source_root / "Network",
]

if not domain_root.is_dir():
    raise SystemExit(f"error: Domain source directory does not exist: {domain_root}")

missing_outward_roots = [str(path) for path in outward_roots if not path.is_dir()]
if missing_outward_roots:
    raise SystemExit(
        "error: expected outward-layer source directories are missing: "
        f"{missing_outward_roots}"
    )


def scrub_swift(source: str) -> str:
    """Remove comments and string contents while preserving line positions."""

    result = list(source)
    length = len(source)
    index = 0
    block_comment_depth = 0

    def blank(start: int, end: int) -> None:
        for position in range(start, end):
            if result[position] not in "\r\n":
                result[position] = " "

    while index < length:
        if block_comment_depth:
            if source.startswith("/*", index):
                blank(index, index + 2)
                block_comment_depth += 1
                index += 2
            elif source.startswith("*/", index):
                blank(index, index + 2)
                block_comment_depth -= 1
                index += 2
            else:
                blank(index, index + 1)
                index += 1
            continue

        if source.startswith("//", index):
            line_end = source.find("\n", index)
            if line_end == -1:
                line_end = length
            blank(index, line_end)
            index = line_end
            continue

        if source.startswith("/*", index):
            blank(index, index + 2)
            block_comment_depth = 1
            index += 2
            continue

        raw_hash_count = 0
        quote_index = index
        if source[index] == "#":
            while quote_index < length and source[quote_index] == "#":
                raw_hash_count += 1
                quote_index += 1

        if quote_index < length and source[quote_index] == '"':
            quote_count = 3 if source.startswith('"""', quote_index) else 1
            opening_end = quote_index + quote_count
            closing = ('"' * quote_count) + ("#" * raw_hash_count)
            blank(index, opening_end)
            cursor = opening_end

            while cursor < length:
                if source.startswith(closing, cursor):
                    blank(cursor, cursor + len(closing))
                    cursor += len(closing)
                    break

                if (
                    quote_count == 1
                    and raw_hash_count == 0
                    and source[cursor] == "\\"
                ):
                    blank(cursor, min(cursor + 2, length))
                    cursor += 2
                    continue

                blank(cursor, cursor + 1)
                cursor += 1

            index = cursor
            continue

        index += 1

    return "".join(result)


declaration_pattern = re.compile(
    r"(?m)^"
    r"(?:(?:public|internal|package|private|fileprivate|open|final|indirect|"
    r"nonisolated)\s+)*"
    r"(?:class|struct|enum|actor|protocol|typealias)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)\b"
)

outward_declarations: dict[str, set[pathlib.Path]] = {}
for outward_root in outward_roots:
    for path in outward_root.rglob("*.swift"):
        source = scrub_swift(path.read_text(encoding="utf-8"))
        for match in declaration_pattern.finditer(source):
            outward_declarations.setdefault(match.group(1), set()).add(path)

forbidden_imports = {
    "Alamofire",
    "AuthenticationServices",
    "FirebaseAuth",
    "GoogleSignIn",
    "GoogleSignInSwift",
    "Moya",
    "SwiftData",
    "SwiftUI",
}
forbidden_import_prefixes = (
    "FBSDK",
    "KakaoSDK",
    "NaverThirdPartyLogin",
)
import_pattern = re.compile(
    r"(?m)^\s*"
    r"(?:(?:@testable|@_exported|@preconcurrency)\s+)*"
    r"import\s+"
    r"(?:(?:class|struct|enum|protocol|func|var|let|typealias)\s+)?"
    r"([A-Za-z_][A-Za-z0-9_]*)"
)

violations: list[str] = []
for path in sorted(domain_root.rglob("*.swift")):
    original = path.read_text(encoding="utf-8")
    source = scrub_swift(original)

    for match in import_pattern.finditer(source):
        module = match.group(1)
        if module in forbidden_imports or module.startswith(
            forbidden_import_prefixes
        ):
            line = source.count("\n", 0, match.start()) + 1
            violations.append(
                f"{path}:{line}: Domain must not import outward framework {module}."
            )

    for name, declaration_paths in outward_declarations.items():
        for match in re.finditer(rf"\b{re.escape(name)}\b", source):
            line = source.count("\n", 0, match.start()) + 1
            owners = ", ".join(str(owner) for owner in sorted(declaration_paths))
            violations.append(
                f"{path}:{line}: Domain references outward-owned type {name} "
                f"(declared in {owners})."
            )

if violations:
    print(
        "Domain dependency boundary failed. Move ports and domain errors into "
        "Domain, then conform or translate in App/Data/Network.",
        file=sys.stderr,
    )
    for violation in violations:
        print(violation, file=sys.stderr)
    raise SystemExit(1)

print(
    "Domain dependency boundary passed "
    "(no forbidden framework imports or outward-owned type references)."
)
PY
