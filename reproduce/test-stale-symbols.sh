#!/bin/bash
#
# test-stale-symbols.sh — Reproduces stale documentSymbol results inside Claude Code.
#
# Asks Claude to get symbols, add a new function, then get symbols again.
# Without the fix, the new function does not appear in the second result
# because typescript-language-server caches navtree by [uri, version] and
# the Claude Code LSP client sends version:1 on every didChange.
#
set -euo pipefail

cd "$(dirname "$0")"

# Reset test files
git checkout -- src/server.ts 2>/dev/null || true

echo "=== Testing Claude Code LSP documentSymbol staleness ==="
echo ""
echo "Asking Claude to get symbols, add a function, then get symbols again..."
echo ""

claude -p "Do the following steps in order:
1. Use the LSP tool to get documentSymbol for src/server.ts. Report all symbol names.
2. Edit src/server.ts to add this new exported function at the end of the file:
   export function newEndpoint(): string {
     return 'hello';
   }
3. Immediately after editing, use the LSP tool to get documentSymbol for src/server.ts again. Report all symbol names.
Compare the two lists. Does newEndpoint appear in the second result?" --output-format text

echo ""
echo "=== Done ==="
echo ""
echo "If newEndpoint does NOT appear in the second documentSymbol result,"
echo "the bug is present (stale navtree cache due to version:1 never changing)."
echo "If newEndpoint DOES appear, the fix is working."

# Reset test files
git checkout -- src/server.ts 2>/dev/null || true
