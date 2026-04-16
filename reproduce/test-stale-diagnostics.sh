#!/bin/bash
#
# test-in-claude-code.sh — Reproduces stale diagnostics inside Claude Code.
#
# Asks Claude to edit a file and immediately check LSP diagnostics.
# Without the fix, Claude reports phantom errors from the pre-edit state.
#
set -euo pipefail

cd "$(dirname "$0")"

# Reset test files
git checkout -- src/app.ts 2>/dev/null || true

echo "=== Testing Claude Code LSP diagnostics ==="
echo ""
echo "Asking Claude to remove formatDate usage and check diagnostics..."
echo ""

claude -p "Do the following steps in order:
1. Use the LSP tool to get diagnostics via \`documentSymbol\` for src/app.ts and report them.
2. Edit src/app.ts to remove the lines that use formatDate (the const date line and the console.log(date) line). Also remove formatDate from the import.
3. Immediately after editing, use the LSP tool again via \`documentSymbol\` to get diagnostics for src/app.ts and report exactly what it says.
Report the diagnostics from step 1 and step 3 verbatim." --output-format text

echo ""
echo "=== Done ==="
echo ""
echo "If you see a phantom error like 'Cannot find name formatDate' on a"
echo "nonexistent line after the edit, the bug is present."
echo "If diagnostics are clean after the edit, the fix is working."

# Reset test files
git checkout -- src/app.ts 2>/dev/null || true
