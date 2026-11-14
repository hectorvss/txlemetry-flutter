#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
SNAPSHOT_FILE="$ROOT_DIR/api/txlemetry_flutter.api.json"
UPDATE=false

while (( "$#" )); do
  key="$1"
  shift
  case "$key" in
    -u|--update)
      UPDATE=true
      ;;
    -\?|-h|--help)
      cat <<'EOF'
Usage: scripts/check-api-dart.sh [--update]

Checks the txlemetry_flutter public Dart API against api/txlemetry_flutter.api.json.
Use --update after intentional public API changes.
EOF
      exit
      ;;
    *)
      echo "Unknown option: $key" >&2
      exit 1
      ;;
  esac
done

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

RAW_API="$TMP_DIR/txlemetry_flutter.raw.api.json"
GENERATED_API="$TMP_DIR/txlemetry_flutter.api.json"

cd "$ROOT_DIR/txlemetry_flutter"
dart run dart_apitool:main extract \
  --input . \
  --output "$RAW_API" \
  --force-use-flutter

dart run "$ROOT_DIR/scripts/annotate-api-dart.dart" "$RAW_API" "$ROOT_DIR/txlemetry_flutter"

"${PYTHON:-python3}" - "$RAW_API" "$GENERATED_API" "$SNAPSHOT_FILE" <<'PY'
import json
import sys
from pathlib import Path

raw_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
def normalize_paths(value, key=""):
    if isinstance(value, dict):
        return {name: normalize_paths(item, name) for name, item in value.items()}
    if isinstance(value, list):
        return [normalize_paths(item, key) for item in value]
    if isinstance(value, str) and key in ("relativePath", "entryPoints", "usages"):
        return value.replace("\\", "/")
    return value


data = normalize_paths(json.loads(raw_path.read_text()))
package_api = data.get("packageApi", {})
# dart_apitool writes a temporary package path that changes on every run.
package_api.pop("packagePath", None)
# Keep the checked-in public API snapshot independent from release bumps.
package_api["packageVersion"] = "<version>"
# File enumeration order differs between platforms. Preserve the baseline's
# declaration order without sorting parameters or other ordered API members.
snapshot_path = Path(sys.argv[3])
baseline = normalize_paths(json.loads(snapshot_path.read_text())).get("packageApi", {}) if snapshot_path.exists() else {}
for collection in ("interfaceDeclarations", "executableDeclarations", "fieldDeclarations", "typeAliasDeclarations"):
    order = {
        (item.get("relativePath", ""), item["name"]): index
        for index, item in enumerate(baseline.get(collection, []))
    }
    package_api.get(collection, []).sort(key=lambda item: (
        order.get((item.get("relativePath", ""), item["name"]), len(order)),
        item.get("relativePath", ""),
        item["name"],
    ))
out_path.write_text(json.dumps(data, indent=4, sort_keys=True) + "\n")
PY

if $UPDATE; then
  mkdir -p "$(dirname "$SNAPSHOT_FILE")"
  cp "$GENERATED_API" "$SNAPSHOT_FILE"
  echo "Updated $SNAPSHOT_FILE"
  exit
fi

if [[ ! -f "$SNAPSHOT_FILE" ]]; then
  echo "Missing public API snapshot: $SNAPSHOT_FILE" >&2
  echo "Run scripts/check-api-dart.sh --update to create it." >&2
  exit 1
fi

if diff -u "$SNAPSHOT_FILE" "$GENERATED_API"; then
  echo "txlemetry_flutter public API snapshot is up to date."
else
  echo "txlemetry_flutter public API changed. Run scripts/check-api-dart.sh --update if intentional." >&2
  exit 1
fi
