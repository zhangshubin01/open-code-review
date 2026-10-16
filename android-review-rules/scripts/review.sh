#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 alibaba/open-code-review Contributors
#
# Team wrapper: always inject the team conventions, then forward every argument
# to ocr review unchanged.
#
#   ./scripts/review.sh
#   ./scripts/review.sh --from main --to HEAD --format json -o /tmp/out.json
#
# The conventions file is run-level context. --background-file takes precedence
# over --background, so a caller passing -b does not silently drop the team
# conventions. Put this on the team's PATH (or alias it) so nobody has to
# remember the flag.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# This script lives at <repo>/scripts/review.sh, so the repo root is one level up.
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONVENTIONS="$REPO_ROOT/.ocr/android-conventions.md"
DEPRECATED="$REPO_ROOT/.ocr/deprecated-apis.md"
# Deterministic path rather than mktemp: exec below replaces this shell, so a
# trap would never fire and a temp file would leak on every run.
MERGED="$REPO_ROOT/.ocr/.review-background.md"

if [[ ! -f "$CONVENTIONS" ]]; then
  echo "error: $CONVENTIONS not found -- copy android-conventions.md into .ocr/ first" >&2
  exit 2
fi

if ! command -v ocr >/dev/null 2>&1; then
  echo "error: ocr is not on PATH -- npm install -g @alibaba-group/open-code-review" >&2
  exit 127
fi

# Refresh the deprecated-API checklist before reviewing, so the rule's source
# of truth is current. stdout is sent to stderr to keep the review output clean.
# Opt out with OCR_SKIP_DEPRECATED_REFRESH=1 when the checklist is already
# current and the lint run is too slow for the moment.
if [[ -z "${OCR_SKIP_DEPRECATED_REFRESH:-}" ]]; then
  if ! "$SCRIPT_DIR/refresh-deprecated-apis.sh" >&2; then
    echo "warning: deprecated-API checklist refresh failed; using the existing checklist if present" >&2
  fi
fi

BACKGROUND="$CONVENTIONS"
if [[ -f "$DEPRECATED" ]]; then
  cat "$CONVENTIONS" "$DEPRECATED" > "$MERGED"
  BACKGROUND="$MERGED"
fi

exec ocr review --background-file "$BACKGROUND" "$@"
