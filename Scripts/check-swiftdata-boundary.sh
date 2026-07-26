#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-Moru/Moru}"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required for SwiftData boundary checks." >&2
  exit 2
fi

violations="$(
  rg -n \
    '(^import SwiftData\b|\bModelContext\b|@Query\b|\bPersisted[A-Za-z0-9_]*\b)' \
    "$ROOT" \
    --glob '*.swift' \
    | rg -v '/Data/(Local|Persistence)/' \
    | rg -v '/App/(AppBootstrapper|DependencyContainer)\.swift:' \
    || true
)"

if [[ -n "$violations" ]]; then
  echo "SwiftData/Persisted access must stay behind repositories and app bootstrap." >&2
  echo "$violations" >&2
  exit 1
fi

python3 - \
  "$ROOT/Data/Persistence/MoruSchema.swift" \
  "$ROOT/Data/Persistence/PersistedModels.swift" \
  "$ROOT/Data/Local/SwiftDataMappers.swift" <<'PY'
import pathlib
import re
import sys

schema_path, models_path, mappers_path = map(pathlib.Path, sys.argv[1:])
schema = schema_path.read_text(encoding="utf-8")
models = models_path.read_text(encoding="utf-8")
mappers = mappers_path.read_text(encoding="utf-8")


def enum_body(name: str, next_name: str) -> str:
    match = re.search(
        rf"enum {name}: VersionedSchema \{{(.*?)\n\}}\n\n"
        rf"enum {next_name}",
        schema,
        re.S,
    )
    if not match:
        raise SystemExit(f"error: could not inspect {name}.")
    return match.group(1)


v3 = enum_body("MoruSchemaV3", "MoruSchemaV4")
v4 = enum_body("MoruSchemaV4", "MoruMigrationPlan")
v3_models = re.findall(r"Persisted[A-Za-z0-9_]+\.self", v3)
v4_models = re.findall(r"Persisted[A-Za-z0-9_]+\.self", v4)
expected_additions = [
    "PersistedServerMutation.self",
    "PersistedVoiceCatalogEntry.self",
]

if any(model in v3_models for model in expected_additions):
    raise SystemExit("error: account-scoped P6 models must not be added to MoruSchemaV3.")
if v4_models != v3_models + expected_additions:
    raise SystemExit(
        "error: MoruSchemaV4 must be exactly V3 plus the P6 Outbox and voice cache; "
        f"found additions/order {v4_models}."
    )

required_schema_contracts = [
    "static let versionIdentifier = Schema.Version(4, 0, 0)",
    ".lightweight(fromVersion: MoruSchemaV3.self, toVersion: MoruSchemaV4.self)",
    "let schema = Schema(versionedSchema: MoruSchemaV4.self)",
]
missing_schema = [value for value in required_schema_contracts if value not in schema]
if missing_schema:
    raise SystemExit(f"error: missing explicit V4 migration contracts: {missing_schema}")

for declaration in [
    "@Model\nfinal class PersistedServerMutation",
    "@Model\nfinal class PersistedVoiceCatalogEntry",
]:
    if declaration not in models:
        raise SystemExit(f"error: missing P6 persisted model declaration: {declaration}")

required_local_only_contracts = [
    "guard syncStatus == .localOnly else",
    'SwiftDataMappingError.nonLocalSyncMetadata(field: "remoteID")',
    'SwiftDataMappingError.nonLocalSyncMetadata(field: "lastSyncedAt")',
    'SwiftDataMappingError.nonLocalSyncMetadata(field: "remoteRevision")',
    "status: .localOnly",
]
missing_local_only = [
    value for value in required_local_only_contracts if value not in mappers
]
if missing_local_only:
    raise SystemExit(
        "error: P6 must preserve the Routine/Run localOnly mapper contract; "
        f"missing {missing_local_only}"
    )

for forbidden in ["deletedAt", "pendingDelete", "includeDeleted"]:
    if forbidden in models or forbidden in mappers:
        raise SystemExit(
            f"error: P6 must not introduce soft-delete contract {forbidden!r}."
        )
PY

echo "SwiftData boundary and exact V4 schema contract checks passed."
