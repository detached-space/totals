'use strict';
// Front-end #1: convert the exported ios-files/ JSONL into the app's import JSON.
//
// Usage:  node convert-files.js <ios-files-dir> [out.json]
//
// Fidelity note: transactions with no bank `reference` were identified in the old app
// by a synthetic `tx-<insertionIndex>` id that is NOT stored in the export and cannot be
// reconstructed from the files. Category tags / account overrides / notes that key off a
// `tx-<index>` id therefore cannot be re-attached here (they are counted and listed).
// Everything keyed by a real bank reference migrates. For a lossless migration, use
// export-from-old-app.js instead.

const fs = require('fs');
const path = require('path');
const { buildImportJson } = require('./mapping');

function readJsonl(dir, name) {
  const p = path.join(dir, name);
  if (!fs.existsSync(p)) return [];
  const out = [];
  for (const line of fs.readFileSync(p, 'utf8').split('\n')) {
    const s = line.trim();
    if (!s) continue;
    try { out.push(JSON.parse(s)); } catch (_) { /* skip malformed line */ }
  }
  return out;
}

function isSynthetic(txId) { return typeof txId === 'string' && /^tx-\d+$/.test(txId); }

function main() {
  const dir = process.argv[2];
  const outPath = process.argv[3] || path.join(dir || '.', 'totals-import.json');
  if (!dir || !fs.existsSync(dir)) {
    console.error('Usage: node convert-files.js <ios-files-dir> [out.json]');
    process.exit(1);
  }

  const transactions = readJsonl(dir, 'transactions.txt');
  const categoriesFile = readJsonl(dir, 'categories.txt');
  const reasonsFile = readJsonl(dir, 'reasons.txt');
  const overridesFile = readJsonl(dir, 'account_overrides.txt');
  const customCategories = readJsonl(dir, 'custom_categories.txt');
  const categoryRules = readJsonl(dir, 'category_rules.txt');
  const accounts = readJsonl(dir, 'accounts.txt');
  const contacts = readJsonl(dir, 'contacts.txt');
  const profiles = readJsonl(dir, 'profiles.txt');
  const budgetsFile = readJsonl(dir, 'budgets.txt');
  const failedParsings = readJsonl(dir, 'failed_parsings.txt');

  // Each transaction's txId. Lossless if the export included `.id` (from the old app's
  // resolved State — see export-from-old-app.js); otherwise the bank reference, and
  // reference-less transactions (synthetic tx-<index>) can't be matched.
  const hasIds = transactions.some((t) => t && t.id);
  const byTxId = new Map();
  let dupRefs = 0;
  for (const tx of transactions) {
    const txId = tx.id || ((tx.reference || '').trim() || null);
    tx.__txId = txId;
    if (!txId) continue;
    if (byTxId.has(txId)) { dupRefs++; continue; } // first wins
    byTxId.set(txId, tx);
  }

  // Metadata keyed by txId. An entry is "unrecovered" only if its txId isn't present
  // (i.e., a tx-<index> id when the transactions file lacks `.id`).
  const manualCats = new Map();
  let catUnrecovered = 0;
  for (const c of categoriesFile) {
    if (!byTxId.has(c.txId)) { catUnrecovered++; continue; }
    manualCats.set(c.txId, Array.isArray(c.categories) ? c.categories : []);
  }
  const reasons = new Map();
  let reasonUnrecovered = 0;
  for (const r of reasonsFile) {
    if (!byTxId.has(r.txId)) { reasonUnrecovered++; continue; }
    reasons.set(r.txId, r.reason);
  }
  const overrides = new Map();
  let overrideUnrecovered = 0;
  for (const o of overridesFile) {
    if (!byTxId.has(o.txId)) { overrideUnrecovered++; continue; }
    overrides.set(o.txId, { accountNumber: o.accountNumber, bankId: o.bankId });
  }

  // Auto-category rules: receiver(lower) -> [category names]
  const rulesByReceiver = new Map();
  for (const r of categoryRules) {
    const k = (r.receiver || '').trim().toLowerCase();
    if (!k) continue;
    if (!rulesByReceiver.has(k)) rulesByReceiver.set(k, []);
    rulesByReceiver.get(k).push(r.category);
  }

  // Account-number -> profile membership (for tx.profileNumber)
  const acctToProfileIdx = new Map();
  profiles.forEach((p, i) => (p.accounts || []).forEach((num) => acctToProfileIdx.set(String(num).trim(), i)));

  // Resolve each transaction (replicating the old app: manual tags override rule tags).
  const resolvedTxs = transactions.map((tx) => {
    const txId = tx.__txId;
    let categories = [];
    if (txId && manualCats.has(txId)) {
      categories = manualCats.get(txId);
    } else {
      const rk = (tx.receiver || '').trim().toLowerCase();
      if (rk && rulesByReceiver.has(rk)) categories = rulesByReceiver.get(rk).slice();
    }
    const override = txId && overrides.has(txId) ? overrides.get(txId) : null;
    // Profile: prefer the account this tx resolves to; fall back to its own account string.
    const acctKey = override ? String(override.accountNumber).trim() : null;
    let profileNumber = null;
    if (acctKey && acctToProfileIdx.has(acctKey)) profileNumber = acctToProfileIdx.get(acctKey);
    return {
      id: txId,
      amount: tx.amount,
      reference: tx.reference,
      account: tx.account,
      receiver: tx.receiver,
      vat: tx.vat,
      serviceCharge: tx.serviceCharge,
      totalFees: tx.totalFees,
      balance: tx.balance,
      bankId: tx.bankId,
      type: tx.type,
      timestamp: tx.timestamp,
      categories,
      reason: txId && reasons.has(txId) ? reasons.get(txId) : null,
      overrideAccount: override,
      profileNumber,
    };
  });

  const resolved = {
    transactions: resolvedTxs,
    customCategories,
    accounts,
    budgets: {
      groups: budgetsFile.filter((b) => b.type === 'group'),
      budgets: budgetsFile.filter((b) => b.type === 'budget'),
    },
    profiles,
    categoryRules,
    contacts,
    failedParsings,
  };

  const { payload, stats, warnings } = buildImportJson(resolved);
  fs.writeFileSync(outPath, JSON.stringify(payload, null, 2));

  const unrecovered = catUnrecovered + reasonUnrecovered + overrideUnrecovered;
  console.log('=== iOS file migration ===');
  console.log('mode  :', hasIds ? 'LOSSLESS (transactions include .id from the old app)' : 'from raw files (reference-matched)');
  console.log('output:', outPath);
  console.log('stats :', JSON.stringify(stats, null, 2));
  if (dupRefs) console.log(`note  : ${dupRefs} duplicate transaction id(s) (first kept)`);
  console.log(`unrecovered tx-<index> links: categories=${catUnrecovered}, overrides=${overrideUnrecovered}, notes=${reasonUnrecovered}  → total ${unrecovered}`);
  if (warnings.length) { console.log('warnings:'); warnings.forEach((w) => console.log('  - ' + w)); }
}

main();
