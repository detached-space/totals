# iOS workaround → new Totals app: data migration

Migrates data from the old **Scriptable-based iOS Totals** (JSONL files in iCloud) into
the new Flutter app via its built-in **Import Backup**. Two paths, same output (a
schema-v8 `totals-import.json`); pick by how much fidelity you need.

```
migration/
  mapping.js                      shared old → schema-v8 transform (source of truth)
  convert-files.js                PATH A — convert the exported ios-files/ (lossy-small)
  export-from-old-app.js          PATH B — front-end that runs in the live old app (lossless)
  export-from-old-app.bundled.js  PATH B — mapping.js + front-end in one paste-able file (generated)
```

## Which path?

| | Path A — from files | Path B — from the live app |
|---|---|---|
| Input | the exported `ios-files/` folder | the old app running on your phone |
| Needs a computer | yes (Node) | no |
| Fidelity | ~98% — loses **48 links** (37 category tags + 11 account overrides) on reference-less transactions | **lossless** |
| Why the loss | those transactions were keyed by a synthetic `tx-<index>` id that isn't stored in the files and can't be reconstructed | the live app still has each transaction's `.id` + resolved `.categories` in memory |

Everything else is identical between the two: all transactions (reference-less ones get a
stable synthesized reference so they aren't skipped on import), notes, custom categories,
auto-category rules, budgets, accounts, contacts, and profiles.

## Path A — convert the exported files
```
node convert-files.js /path/to/ios-files  out.json
```
Prints stats and the exact count of unrecoverable `tx-<index>` links. Import `out.json`
into the app (below).

## Path B — lossless, from the live old app
1. Open the old Totals app so its data is loaded.
2. Run `export-from-old-app.bundled.js` in the app's WebView JS context — e.g. paste it
   into the WebView console, or `evaluateJavaScript(<bundle>)` from a Scriptable wrapper.
   It reads the live `State`, builds the import JSON, and downloads **`totals-import.json`**
   (also left on `window.__totalsImportJson`).
   - Rebuild the bundle after editing sources: `cat mapping.js export-from-old-app.js > export-from-old-app.bundled.js` (prepend the mapping first).

## Import into the new app
Settings → **Import Backup** → pick `totals-import.json`. The importer de-duplicates
(by transaction reference, category name+flow, etc.), so re-importing is safe.

## Fidelity notes & known gaps
- **Reference-less transactions** get a deterministic `iosmig-<hash>` reference so they
  import and de-dupe on re-import.
- **Categories** are matched by `(name, flow)`; built-ins auto-match, customs are created
  with their colour and income/expense flow (flow inferred from usage when not declared).
- **Auto-category rules**: the app allows one category per `(receiver, flow)`, so a
  receiver mapped to multiple categories collapses to one (reported as a warning).
- **Budgets** are approximate: the app has no budget *groups* or per-month *overrides*, so
  those are dropped (group name is retained on `_group` for reference only).
- **Profiles**: the migration JSON carries a `profiles` section + per-account/transaction
  membership, but the app's importer does **not consume it yet** — profiles need the
  importer extension (pending decision), otherwise everything lands in one profile.
- **Account balances** import as 0; the app derives displayed balances from transactions.
- `failed_parsings` are imported as failed-parse records (empties skipped); `backlog.txt`
  is ignored (raw unparsed SMS, not transactions).
```
