#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 alibaba/open-code-review Contributors
#
# Regenerate the deprecated-API checklist from an Android Lint report.
#
#   ./scripts/refresh-deprecated-apis.sh app/build/reports/lint-results-debug.xml
#
# The checklist is what makes the "deprecated API" rule trustworthy: a model
# asked to spot deprecated APIs from memory is unreliable, a model asked to
# match calls against an explicit list is not. Lint supplies the list, this
# script only formats it. The replacement column is left for a human, because
# lint reports the deprecation but rarely the migration path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPORT="${1:-}"
ISSUE_ID="${OCR_DEPRECATED_ISSUE_ID:-Deprecated}"
# This script lives at <repo>/scripts/, so the checklist is written to <repo>/.ocr/.
OUT="${OCR_DEPRECATED_OUT:-$SCRIPT_DIR/../.ocr/deprecated-apis.md}"
# The generated prose lives in a Markdown template next to this script, not
# inline, so the shell source stays English-only.
TEMPLATE="${OCR_DEPRECATED_TEMPLATE:-$SCRIPT_DIR/deprecated-apis.template.md}"

if [[ -z "$REPORT" ]]; then
  echo "usage: $0 <lint-results-*.xml>" >&2
  echo "  generate one with: ./gradlew lint   (report lands under <module>/build/reports/)" >&2
  exit 2
fi

if [[ ! -f "$REPORT" ]]; then
  echo "error: $REPORT not found" >&2
  exit 2
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "error: $TEMPLATE not found -- keep it next to refresh-deprecated-apis.sh" >&2
  exit 2
fi

python3 - "$REPORT" "$ISSUE_ID" "$OUT" "$TEMPLATE" <<'PY'
import sys
import xml.etree.ElementTree as ET
from datetime import date

report, issue_id, out, template_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

try:
    root = ET.parse(report).getroot()
except ET.ParseError as exc:
    sys.exit(f"error: could not parse {report}: {exc}")

with open(template_path, encoding="utf-8") as fh:
    template = fh.read()


def cell(text):
    return text.replace("|", "\\|").replace("\n", " ").strip()


found = []
for issue in root.iter("issue"):
    if issue.get("id") != issue_id:
        continue
    locations = [
        f"{loc.get('file')}:{loc.get('line')}"
        for loc in issue.iter("location")
        if loc.get("file")
    ]
    found.append((cell(issue.get("message", "")), locations))

if not found:
    sys.exit(
        f'error: no <issue id="{issue_id}"> entries in {report}.\n'
        f"       list the ids present with:\n"
        f"         grep -o 'id=\"[^\"]*\"' {report} | sort -u\n"
        f"       then re-run with OCR_DEPRECATED_ISSUE_ID=<id>"
    )

seen, rows = {}, []
for message, locations in found:
    if message not in seen:
        seen[message] = []
        rows.append(message)
    seen[message].extend(locations)

lines = []
for message in rows:
    locations = seen[message]
    where = cell(locations[0]) if locations else "(no location given)"
    if len(locations) > 1:
        where += f" (+{len(locations) - 1} more)"
    lines.append(f"| `{message}` | {where} | <!-- TODO: replacement --> |")

body = template.format(
    date=date.today().isoformat(),
    source=report,
    issue_id=issue_id,
    rows="\n".join(lines),
)

with open(out, "w", encoding="utf-8") as fh:
    fh.write(body)

print(f"wrote {out}: {len(lines)} distinct messages from {len(found)} lint entries")
PY
