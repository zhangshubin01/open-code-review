#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 alibaba/open-code-review Contributors
#
# Regenerate the deprecated-API checklist from Android Lint.
#
#   ./scripts/refresh-deprecated-apis.sh                    # run ./gradlew lint, then read every report it writes
#   ./scripts/refresh-deprecated-apis.sh <report.xml> ...   # read the given report(s) instead of running lint
#
# The checklist is what makes the "deprecated API" rule trustworthy: a model
# asked to spot deprecated APIs from memory is unreliable, a model asked to
# match calls against an explicit list is not. Lint supplies the list, this
# script only formats it. The replacement column is left for a human, because
# lint reports the deprecation but rarely the migration path.
#
# Auto mode looks under */build/reports/lint-results-*.xml and skips the
# -fatal variants, which duplicate the full report. Override the Gradle task
# with OCR_DEPRECATED_LINT_ARGS, e.g. "lintDebug" or "lint --continue".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ISSUE_ID="${OCR_DEPRECATED_ISSUE_ID:-Deprecated}"
# This script lives at <repo>/scripts/, so the checklist is written to <repo>/.ocr/.
OUT="${OCR_DEPRECATED_OUT:-$SCRIPT_DIR/../.ocr/deprecated-apis.md}"
# The generated prose lives in a Markdown template next to this script, not
# inline, so the shell source stays English-only.
TEMPLATE="${OCR_DEPRECATED_TEMPLATE:-$SCRIPT_DIR/deprecated-apis.template.md}"
read -ra LINT_ARGS <<< "${OCR_DEPRECATED_LINT_ARGS:-lint}"

REPORTS=("$@")
AUTO=false
[[ ${#REPORTS[@]} -gt 0 ]] || AUTO=true

find_repo_root() {
  local dir="$SCRIPT_DIR"
  while [[ "$dir" != "/" ]]; do
    if [[ -x "$dir/gradlew" ]]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

if $AUTO; then
  REPO_ROOT="$(find_repo_root)" || {
    echo "error: could not find gradlew above $SCRIPT_DIR -- run from inside an Android repo" >&2
    exit 2
  }
  echo "running: ./gradlew ${LINT_ARGS[*]}  (in $REPO_ROOT)" >&2
  (cd "$REPO_ROOT" && ./gradlew "${LINT_ARGS[@]}")

  while IFS= read -r report; do
    [[ -n "$report" ]] && REPORTS+=("$report")
  done < <(cd "$REPO_ROOT" && find . -name 'lint-results-*.xml' ! -name '*-fatal.xml' -print 2>/dev/null | grep '/build/reports/' | sed 's|^\./||' | sort)
  RUN_DIR="$REPO_ROOT"
else
  RUN_DIR="."
fi

if [[ ${#REPORTS[@]} -eq 0 ]]; then
  echo "error: no lint-results-*.xml found under */build/reports/" >&2
  echo "  run ./gradlew lint first, or pass a report path explicitly:" >&2
  echo "    $0 app/build/reports/lint-results-debug.xml" >&2
  exit 2
fi

for report in "${REPORTS[@]}"; do
  if [[ ! -f "$RUN_DIR/$report" ]]; then
    echo "error: $report not found" >&2
    exit 2
  fi
done

if [[ ! -f "$TEMPLATE" ]]; then
  echo "error: $TEMPLATE not found -- keep it next to refresh-deprecated-apis.sh" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUT")"

cd "$RUN_DIR"
python3 - "$ISSUE_ID" "$OUT" "$TEMPLATE" "${REPORTS[@]}" <<'PY'
import sys
import xml.etree.ElementTree as ET
from datetime import date

issue_id, out, template_path = sys.argv[1], sys.argv[2], sys.argv[3]
reports = sys.argv[4:]

with open(template_path, encoding="utf-8") as fh:
    template = fh.read()


def cell(text):
    return text.replace("|", "\\|").replace("\n", " ").strip()


found = []
for report in reports:
    try:
        root = ET.parse(report).getroot()
    except (ET.ParseError, OSError) as exc:
        sys.exit(f"error: could not parse {report}: {exc}")
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
        f'error: no <issue id="{issue_id}"> entries in the given report(s).\n'
        f"       list the ids present with:\n"
        f"         grep -o 'id=\"[^\"]*\"' <report> | sort -u\n"
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
    source=", ".join(reports),
    issue_id=issue_id,
    rows="\n".join(lines),
)

with open(out, "w", encoding="utf-8") as fh:
    fh.write(body)

print(f"wrote {out}: {len(lines)} distinct messages from {len(found)} lint entries")
PY
