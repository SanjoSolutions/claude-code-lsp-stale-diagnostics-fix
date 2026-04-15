# Stale TypeScript LSP Diagnostics in Claude Code

After file edits, Claude Code reads LSP diagnostics before the TypeScript language server has finished processing the change. This causes Claude to receive phantom errors about code that no longer exists, wasting a turn to investigate before moving on.

Related issues: [#17979](https://github.com/anthropics/claude-code/issues/17979), [#41637](https://github.com/anthropics/claude-code/issues/41637)

Tested on: Claude Code 2.1.104, 2.1.109

## The bug

When Claude edits a TypeScript file (e.g. removes an import or variable), the diagnostic collector (`getLSPDiagnosticAttachments`) runs immediately — before the `textDocument/publishDiagnostics` notification arrives from the language server. Claude receives stale diagnostics from the pre-edit state and reports errors that don't exist.

**Timeline without fix:**

```
Edit tool writes file
  → textDocument/didChange sent to tsserver
  → getLSPDiagnosticAttachments runs immediately (reads stale registry)
  → Claude sees phantom errors, wastes a turn
  ...364ms later...
  → textDocument/publishDiagnostics arrives (fresh, but too late)
```

**Timeline with fix:**

```
Edit tool writes file
  → textDocument/didChange sent to tsserver
  → getLSPDiagnosticAttachments awaits publishDiagnostics notification
  ...364ms later...
  → textDocument/publishDiagnostics arrives, resolves the promise
  → getLSPDiagnosticAttachments reads fresh diagnostics
  → Claude sees correct state
```

## Root cause (for core developers)

The race condition is between three functions in `cli.js`:

### 1. File change notification

When Claude edits a file, the LSP client sends `textDocument/didChange` to the language server.

### 2. Diagnostic storage

The `publishDiagnostics` notification handler stores incoming diagnostics in a registry (`Ss`, a `Map`).

### 3. Diagnostic delivery

Between model turns, `getLSPDiagnosticAttachments` drains the registry and delivers diagnostics as passive feedback.

**The problem:** Step 3 runs before step 2 completes. The `publishDiagnostics` notification takes ~300-400ms to arrive after `didChange` (due to tsserver processing + 200ms request debounce + 50ms publish debounce in typescript-language-server). But `getLSPDiagnosticAttachments` reads the registry immediately, finding either stale pre-edit diagnostics or an empty registry.

### The fix

In `getLSPDiagnosticAttachments` wait for `publishDiagnostics` notification to have happened, before reading.

### Proper fix suggestion

(Suggested by Claude Code. Not verified that it makes sense.)

The patch above uses `globalThis` to bridge across scopes in the minified bundle. A proper implementation in the source code would:

1. Add a `pendingDiagnostics: Promise | null` field to the LSP client manager
2. Set it in the `syncFileChange` method
3. Resolve it in the `publishDiagnostics` handler
4. Await it in `getLSPDiagnosticAttachments`

This is the standard LSP client pattern — equivalent to Neovim's [`vim.lsp.diagnostic.on_publish_diagnostics`](https://neovim.io/doc/user/lsp.html) waiting for notifications before presenting results.

## Reproduce

### Prerequisites

```bash
npm install -g typescript-language-server typescript
```

The `typescript-lsp` plugin must be installed in Claude Code:

```
claude plugin install typescript-lsp
```

### Steps

```bash
cd reproduce
npm install
./test-in-claude-code.sh
```

This asks Claude to edit a TypeScript file (remove `formatDate` usage and its import) and immediately check LSP diagnostics. Without the fix, Claude reports a stale phantom error like:

> ✘ [Line 6:14] Cannot find name 'formatDate'. Did you mean 'formatName'? [2552] (typescript)
>
> This diagnostic references line 6 character 14 with `formatDate`, but the file no longer has a line 6 or any reference to `formatDate`. This is a classic stale diagnostics problem.

With the fix applied, no phantom diagnostic errors appear after the edit.

## Fix

```bash
./fix.sh
```

The script patches `cli.js` in-place (with backup). It auto-detects the Claude Code version and makes three or four changes:

1. **After `textDocument/didChange`** — creates a promise that will resolve when diagnostics arrive (with a 5-second timeout safety net)
2. **In the `publishDiagnostics` handler** — resolves the promise when fresh diagnostics are stored
3. **In `getLSPDiagnosticAttachments`** — awaits the promise before reading the diagnostic registry
4. **In the new MCP-based diagnostic function** (v2.1.109+) — awaits the promise before querying `getNewDiagnostics`

Note: v2.1.109 added a second diagnostic code path that queries diagnostics via an MCP client (`getNewDiagnostics`), alongside the original registry-based path. Both paths need the wait.

To revert:

```bash
./fix.sh --revert
```

**Note:** The patch will be overwritten when Claude Code updates. Re-run `./fix.sh` after updating.
