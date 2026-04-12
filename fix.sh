#!/bin/bash
#
# fix.sh — Patches Claude Code to fix stale TypeScript LSP diagnostics.
#
# Makes getLSPDiagnosticAttachments await the publishDiagnostics notification
# instead of reading the registry immediately after file edits.
#
# Usage:
#   ./fix.sh           # Apply the patch
#   ./fix.sh --revert  # Restore from backup
#
# Tested on: Claude Code 2.1.104
#
set -euo pipefail

# Find cli.js — try require.resolve, fall back to common locations
find_cli_js() {
  local result
  result=$(node -e "console.log(require.resolve('@anthropic-ai/claude-code/cli.js'))" 2>/dev/null) && { echo "$result"; return; }

  # Check common global install locations
  for dir in \
    "$HOME/.nvm/versions/node"/*/lib/node_modules/@anthropic-ai/claude-code \
    /usr/lib/node_modules/@anthropic-ai/claude-code \
    /usr/local/lib/node_modules/@anthropic-ai/claude-code \
    "$HOME/.local/share/pnpm/global"/*/node_modules/@anthropic-ai/claude-code
  do
    if [ -f "$dir/cli.js" ]; then
      echo "$dir/cli.js"
      return
    fi
  done

  return 1
}

CLI_JS=$(find_cli_js) || {
  echo "Error: Could not find Claude Code cli.js. Is it installed via npm?"
  exit 1
}

echo "Found cli.js at: $CLI_JS"

# --- Revert mode ---
if [ "${1:-}" = "--revert" ]; then
  if [ ! -f "$CLI_JS.bak" ]; then
    echo "Error: No backup found at $CLI_JS.bak"
    exit 1
  fi
  cp "$CLI_JS.bak" "$CLI_JS"
  echo "Reverted to backup. Restart Claude Code for changes to take effect."
  exit 0
fi

# --- Check if already patched ---
if grep -q '__lspPendingDiag' "$CLI_JS"; then
  echo "Already patched. Nothing to do."
  exit 0
fi

# --- Validate patch targets exist ---
TARGETS=(
  'N(`LSP: Sent didChange for ${P}`)'
  'Np4({serverName:O,files:H}),N(`LSP Diagnostics: Registered'
  'getLSPDiagnosticAttachments called");try{let K=yp4()'
)

for marker in "${TARGETS[@]}"; do
  if ! grep -qF "$marker" "$CLI_JS"; then
    echo "Error: Could not find expected code pattern."
    echo "This patch may not be compatible with your Claude Code version."
    echo "Missing: $marker"
    exit 1
  fi
done

# --- Backup ---
cp "$CLI_JS" "$CLI_JS.bak"
echo "Backup saved to: $CLI_JS.bak"

# --- Patch ---

# 1. After didChange: create a promise that resolves when publishDiagnostics arrives
sed -i 's|N(`LSP: Sent didChange for ${P}`)|N(`LSP: Sent didChange for ${P}`);globalThis.__lspPendingDiag=new Promise(r=>{globalThis.__lspDiagResolve=r;setTimeout(r,5000)})|' "$CLI_JS"

# 2. In publishDiagnostics handler: resolve the promise
sed -i 's|Np4({serverName:O,files:H}),N(`LSP Diagnostics: Registered|Np4({serverName:O,files:H}),globalThis.__lspDiagResolve\&\&(globalThis.__lspDiagResolve(),globalThis.__lspDiagResolve=null),N(`LSP Diagnostics: Registered|' "$CLI_JS"

# 3. In getLSPDiagnosticAttachments: await the promise before reading
sed -i 's|getLSPDiagnosticAttachments called");try{let K=yp4()|getLSPDiagnosticAttachments called");try{if(globalThis.__lspPendingDiag){await globalThis.__lspPendingDiag;globalThis.__lspPendingDiag=null}let K=yp4()|' "$CLI_JS"

# --- Verify ---
if ! grep -q '__lspPendingDiag' "$CLI_JS"; then
  echo "Error: Patch verification failed. Restoring backup."
  cp "$CLI_JS.bak" "$CLI_JS"
  exit 1
fi

echo "Patched successfully. Restart Claude Code for changes to take effect."
echo "To revert: $0 --revert"
