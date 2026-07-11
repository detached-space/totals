// AUTO-GENERATED bundle: mapping.js + export-from-old-app.js. Do not edit; edit the sources.
'use strict';
// Shared mapping: old Totals (iOS Scriptable) resolved data -> new app import JSON (schema v8).
//
// Both front-ends produce the same `resolved` shape and call buildImportJson():
//   - convert-files.js  : resolves from the exported ios-files/ JSONL (lossy for tx-<index> links)
//   - export-from-old-app.js : reads the old app's already-resolved in-memory State (lossless)
//
// `resolved` = {
//   transactions: [{ id, amount, reference, account, receiver, vat, serviceCharge,
//                    totalFees, balance, bankId, type, timestamp,
//                    categories:[name], reason:string|null,
//                    overrideAccount:{accountNumber,bankId}|null, profileNumber:string|null }],
//   customCategories: [{ name, color, type }],       // type: 'income'|'expense'|'both'
//   accounts:         [{ number, bankId, name, isDefault, createdAt }],
//   budgets:          { groups:[{name,order}], budgets:[{...}] },
//   profiles:         [{ id, name, accounts:[number], color, order }],
//   categoryRules:    [{ receiver, category }],
//   contacts:         [{ name, number, bankId, createdAt }],
//   failedParsings:   [{ message, timestamp }],
// }

const SCHEMA_VERSION = 8;
const SOURCE_TYPE = 'ios_migration';

function normText(v) {
  if (v === null || v === undefined) return '';
  return String(v).trim();
}

function normalizeCounterparty(v) {
  return normText(v).replace(/\s+/g, ' ').toLowerCase();
}

// The app stores accountNumber as the last 4 digits. For masked accounts the true
// suffix is the digits after the last mask char (else last-4 of all digits).
function last4(accountLike) {
  const s = normText(accountLike);
  if (!s) return null;
  const star = s.lastIndexOf('*');
  const tail = star >= 0 ? s.slice(star + 1) : s;
  let digits = tail.replace(/\D/g, '');
  if (!digits) digits = s.replace(/\D/g, '');
  return digits ? digits.slice(-4) : null;
}

// Parse an amount/balance like the old app: strip thousands commas / currency / trailing
// junk ("1,000" -> 1000, "833.16." -> 833.16); tolerate numbers and strings.
function parseAmount(v) {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number') return v;
  let s = String(v).trim();
  if (!s) return null;
  s = s.replace(/[^0-9.]/g, '');
  const firstDot = s.indexOf('.');
  if (firstDot !== -1) s = s.slice(0, firstDot + 1) + s.slice(firstDot + 1).replace(/\./g, '');
  if (s.endsWith('.')) s += '0';
  if (!s || s === '.') return null;
  const n = Number(s);
  return isNaN(n) ? null : n;
}

function toIso(ts) {
  if (!ts) return null;
  const s = normText(ts);
  // Already ISO-ish? Trust it. Otherwise try Date parse.
  if (/^\d{4}-\d{2}-\d{2}T/.test(s)) return s;
  const d = new Date(s);
  return isNaN(d.getTime()) ? null : d.toISOString();
}

function numOrNull(v) {
  if (v === '' || v === null || v === undefined) return null;
  const n = Number(v);
  return isNaN(n) ? null : n;
}

// Deterministic short hash (FNV-1a) so a reference-less transaction gets a stable,
// collision-proof synthetic reference (survives re-import via the app's dedup).
function fnv1a(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(36);
}

function syntheticReference(tx) {
  const key = [tx.amount, tx.timestamp, tx.bankId, tx.balance, tx.type, tx.account]
    .map(normText).join('|');
  return 'iosmig-' + fnv1a(key);
}

function buildImportJson(resolved, opts = {}) {
  const warnings = [];
  const txs = resolved.transactions || [];

  // 1) Category flow inference: majority vote from tagged transactions (credit->income).
  const customByName = new Map();
  for (const c of resolved.customCategories || []) {
    customByName.set(normText(c.name).toLowerCase(), c);
  }
  const usage = new Map(); // name(lower) -> {credit, debit, name}
  for (const tx of txs) {
    const isCredit = normText(tx.type).toUpperCase() === 'CREDIT';
    for (const cn of tx.categories || []) {
      const k = normText(cn).toLowerCase();
      if (!usage.has(k)) usage.set(k, { credit: 0, debit: 0, name: normText(cn) });
      usage.get(k)[isCredit ? 'credit' : 'debit']++;
    }
  }

  function flowFor(name) {
    const k = normText(name).toLowerCase();
    const custom = customByName.get(k);
    if (custom && custom.type && custom.type !== 'both') {
      return custom.type === 'income' ? 'income' : 'expense';
    }
    const u = usage.get(k);
    if (u && (u.credit || u.debit)) return u.credit > u.debit ? 'income' : 'expense';
    return 'expense';
  }

  // 2) Category registry: distinct (name, flow) -> synthetic id. Include every name
  //    seen in tags, custom defs, budgets and rules so the importer can match/create it.
  const catId = new Map(); // `${name}|${flow}` -> id
  const categories = [];
  let nextCatId = 1;
  function registerCategory(name, flowOverride) {
    const nm = normText(name);
    if (!nm) return null;
    const flow = flowOverride || flowFor(nm);
    const key = `${nm.toLowerCase()}|${flow}`;
    if (catId.has(key)) return catId.get(key);
    const id = nextCatId++;
    catId.set(key, id);
    const custom = customByName.get(nm.toLowerCase());
    categories.push({
      id,
      name: nm,
      flow,
      colorKey: custom && custom.color ? custom.color : null,
      essential: false,
      uncategorized: false,
      recurring: false,
      builtIn: false,
    });
    return id;
  }
  // Seed from custom defs (respect their declared flow, incl. 'both' -> expense).
  for (const c of resolved.customCategories || []) {
    if (c.type === 'both') warnings.push(`custom category "${c.name}" is type "both"; imported as expense`);
    registerCategory(c.name, c.type === 'income' ? 'income' : 'expense');
  }

  // 3) Transactions
  const usedRefs = new Set();
  let synthRefCount = 0, dupRefCount = 0;
  const outTransactions = txs.map((tx) => {
    let reference = normText(tx.reference);
    if (!reference) { reference = syntheticReference(tx); synthRefCount++; }
    // Guarantee uniqueness (app requires unique reference).
    let ref = reference;
    while (usedRefs.has(ref)) { ref = reference + '-' + (++dupRefCount); }
    usedRefs.add(ref);

    const catIds = [];
    for (const cn of tx.categories || []) {
      const id = registerCategory(cn);
      if (id) catIds.push(id);
    }

    const acctSource = tx.overrideAccount ? tx.overrideAccount.accountNumber : tx.account;
    const receiver = normText(tx.receiver);
    return {
      amount: parseAmount(tx.amount) || 0,
      reference: ref,
      receiver: receiver && receiver.toLowerCase() !== 'unknown' ? receiver : null,
      note: tx.reason ? normText(tx.reason) : null,
      time: toIso(tx.timestamp),
      currentBalance: (function(){var b=parseAmount(tx.balance);return b===null?null:String(b);})(),
      bankId: numOrNull(tx.bankId),
      type: normText(tx.type).toUpperCase() || null,
      accountNumber: last4(acctSource),
      categoryIds: catIds.length ? catIds : null,
      categoryId: catIds.length ? catIds[0] : null,
      serviceCharge: parseAmount(tx.serviceCharge),
      vat: parseAmount(tx.vat),
      sourceType: SOURCE_TYPE,
      profileNumber: tx.profileNumber || null, // resolved to profileId by the importer extension
    };
  });

  // 4) Accounts
  const outAccounts = (resolved.accounts || []).map((a) => ({
    accountNumber: normText(a.number),
    bank: numOrNull(a.bankId),
    balance: 0, // app derives displayed balance from transactions; see README
    accountHolderName: normText(a.name) || normText(a.number),
    profileNumber: null, // filled from profiles below
  })).filter((a) => a.accountNumber && a.bank !== null);

  // 5) Profiles (non-standard section; consumed by the importer extension) + backfill
  //    account/transaction profile membership by account number.
  const acctToProfile = new Map();
  const outProfiles = (resolved.profiles || []).map((p, i) => {
    for (const num of p.accounts || []) acctToProfile.set(normText(num), i);
    return { index: i, name: normText(p.name), color: p.color || null, order: p.order ?? i,
             accountNumbers: (p.accounts || []).map(normText) };
  });
  for (const a of outAccounts) {
    if (acctToProfile.has(a.accountNumber)) a.profileNumber = acctToProfile.get(a.accountNumber);
  }

  // 6) userAccounts <- contacts
  const outUserAccounts = (resolved.contacts || []).map((c) => ({
    accountNumber: normText(c.number),
    bankId: numOrNull(c.bankId),
    accountHolderName: normText(c.name) || normText(c.number),
    createdAt: toIso(c.createdAt) || new Date(0).toISOString(),
  })).filter((c) => c.accountNumber && c.bankId !== null);

  // 7) Auto-category rules <- category_rules (one per counterparty+flow; last wins in app).
  const outRules = [];
  const seenRule = new Set();
  let ruleCollisions = 0;
  for (const r of resolved.categoryRules || []) {
    const flow = flowFor(r.category);
    const id = registerCategory(r.category);
    if (id === null) continue;
    const norm = normalizeCounterparty(r.receiver);
    if (!norm) continue;
    const key = `${norm}|${flow}`;
    if (seenRule.has(key)) ruleCollisions++;
    seenRule.add(key);
    outRules.push({
      counterparty: normText(r.receiver),
      normalizedCounterparty: norm,
      flow,
      categoryId: id,
      isPrimary: true,
      createdAt: new Date().toISOString(),
    });
  }
  if (ruleCollisions) warnings.push(`${ruleCollisions} auto-category rule(s) collapsed (multiple categories for the same receiver+flow; the app keeps one)`);

  // 8) Budgets (approximate: app has no groups/overrides).
  const bsrc = resolved.budgets || { groups: [], budgets: [] };
  const outBudgets = (bsrc.budgets || []).map((b) => {
    const cids = (b.categories || []).map((n) => registerCategory(n)).filter((x) => x !== null);
    const start = b.month ? `${b.month}-01T00:00:00.000Z` : (toIso(b.createdAt) || new Date().toISOString());
    return {
      name: normText(b.name),
      type: 'category',
      amount: parseAmount(b.assigned) || 0,
      categoryIds: cids.length ? cids : null,
      categoryId: cids.length ? cids[0] : null,
      startDate: start,
      timeFrame: b.recurring ? 'monthly' : 'never',
      isActive: true,
      rollover: false,
      alertThreshold: 80.0,
      createdAt: toIso(b.createdAt) || new Date().toISOString(),
      calendar: 'gregorian',
      _group: b.group || null, // informational; app has no group field
    };
  });
  if ((bsrc.groups || []).length) warnings.push(`budget groups (${(bsrc.groups||[]).map(g=>g.name).join(', ')}) are not represented in the app's budget model`);
  if ((bsrc.budgets || []).some((b) => (b.overrides || []).length)) warnings.push('per-month budget overrides are dropped (no equivalent in the app)');

  // 9) failed parses (optional; skip empties)
  const outFailed = (resolved.failedParsings || [])
    .filter((f) => normText(f.message))
    .map((f) => ({ address: '', body: normText(f.message), reason: 'imported from iOS workaround',
                   timestamp: toIso(f.timestamp) || new Date().toISOString() }));

  const payload = {
    schemaVersion: SCHEMA_VERSION,
    version: '1.0',
    exportDate: opts.exportDate || new Date().toISOString(),
    migratedFrom: 'totals-ios-scriptable',
    categories,
    accounts: outAccounts,
    userAccounts: outUserAccounts,
    transactions: outTransactions,
    budgets: outBudgets,
    autoCategoryRules: outRules,
    failedParses: outFailed,
    profiles: outProfiles, // non-standard; requires the importer extension
  };

  const stats = {
    transactions: outTransactions.length,
    syntheticReferences: synthRefCount,
    categories: categories.length,
    accounts: outAccounts.length,
    userAccounts: outUserAccounts.length,
    budgets: outBudgets.length,
    autoCategoryRules: outRules.length,
    profiles: outProfiles.length,
    failedParses: outFailed.length,
  };

  return { payload, stats, warnings };
}

const __api = { buildImportJson, normalizeCounterparty, last4, toIso, syntheticReference, SCHEMA_VERSION };
if (typeof module !== 'undefined' && module.exports) module.exports = __api;      // Node
if (typeof window !== 'undefined') window.__totalsMapping = __api;                 // old-app WebView

'use strict';
// Front-end #2 (LOSSLESS): runs INSIDE the live old Totals iOS app (its WebView),
// where `State` is loaded and every transaction already carries its correctly-resolved
// `.id`, `.categories` and `.resolvedAccount` in memory. Reading those directly recovers
// the reference-less (`tx-<index>`) category tags and account overrides that the exported
// files can't — so this path loses nothing.
//
// It builds the new app's import JSON (schema v8) and downloads `totals-import.json`.
//
// HOW TO RUN: this file must be paired with mapping.js (which defines
// window.__totalsMapping). Use the pre-bundled `export-from-old-app.bundled.js`
// (mapping + this front-end in one file) and run it in the old app's WebView context —
// e.g. paste into the WebView's JS console, or `WebView.evaluateJavaScript(bundle)` from
// a Scriptable wrapper. See README.md.

(function () {
  if (typeof State === 'undefined' || !State || !Array.isArray(State.transactions)) {
    (typeof alert === 'function' ? alert : console.error)(
      'Run this inside the running Totals app — global `State` with transactions not found.');
    return;
  }
  var M = (typeof window !== 'undefined' && window.__totalsMapping) || (typeof globalThis !== 'undefined' && globalThis.__totalsMapping);
  if (!M || !M.buildImportJson) {
    (typeof alert === 'function' ? alert : console.error)(
      'mapping.js not loaded (window.__totalsMapping missing). Use export-from-old-app.bundled.js.');
    return;
  }

  // Auto-category rules by receiver (lowercased) -> [category names], to fill in
  // rule-based tags on transactions that have no manual tag (mirrors convert-files.js).
  var rulesByReceiver = {};
  (State.categoryRules || []).forEach(function (r) {
    var k = String(r.receiver || '').trim().toLowerCase();
    if (!k) return;
    (rulesByReceiver[k] = rulesByReceiver[k] || []).push(r.category);
  });

  // Reason lookup — tolerant of whichever field the app uses.
  var reasonMap = State.reasonMap || State.reasons || State.reasonsMap || {};
  function reasonFor(id) {
    if (reasonMap && typeof reasonMap.get === 'function') return reasonMap.get(id) || null;
    return (reasonMap && reasonMap[id]) || null;
  }

  var transactions = State.transactions.map(function (t) {
    var manual = Array.isArray(t.categories) ? t.categories.slice() : [];
    var categories = manual;
    if (!categories.length) {
      var rk = String(t.receiver || '').trim().toLowerCase();
      if (rk && rulesByReceiver[rk]) categories = rulesByReceiver[rk].slice();
    }
    var acct = t.resolvedAccount && t.resolvedAccount.number ? t.resolvedAccount.number : t.account;
    return {
      id: t.id,
      amount: t.amount,
      reference: t.reference && t.reference !== 'N/A' ? t.reference : '',
      account: acct,
      receiver: t.receiver,
      vat: t.vat,
      serviceCharge: t.serviceCharge,
      totalFees: t.totalFees,
      balance: t.balance,
      bankId: t.bankId,
      type: t.type,
      timestamp: t.timestamp instanceof Date ? t.timestamp.toISOString() : t.timestamp,
      categories: categories,
      reason: reasonFor(t.id),
      overrideAccount: null, // already folded into `account` via resolvedAccount
      profileNumber: null,   // filled below
    };
  });

  var resolved = {
    transactions: transactions,
    customCategories: State.customCategories || [],
    accounts: (State.accounts || []).map(function (a) {
      return { number: a.number, bankId: a.bankId, name: a.name, isDefault: a.isDefault, createdAt: a.createdAt };
    }),
    budgets: { groups: State.budgetGroups || [], budgets: State.budgets || [] },
    profiles: (State.profiles || []).map(function (p) {
      return { id: p.id, name: p.name, accounts: p.accounts, color: p.color, order: p.order };
    }),
    categoryRules: State.categoryRules || [],
    contacts: State.contacts || [],
    failedParsings: State.failedParsings || State.failedParses || [],
  };

  // Transaction profile membership by resolved account number.
  var acctToProfile = {};
  resolved.profiles.forEach(function (p, i) {
    (p.accounts || []).forEach(function (n) { acctToProfile[String(n).trim()] = i; });
  });
  transactions.forEach(function (t) {
    var an = t.account ? String(t.account).trim() : null;
    if (an && acctToProfile.hasOwnProperty(an)) t.profileNumber = acctToProfile[an];
  });

  var result = M.buildImportJson(resolved);
  console.log('[totals-migration] stats:', result.stats);
  if (result.warnings && result.warnings.length) console.log('[totals-migration] warnings:', result.warnings);

  var json = JSON.stringify(result.payload, null, 2);

  // Try to download; otherwise stash for manual retrieval (or Scriptable to read back).
  try {
    var blob = new Blob([json], { type: 'application/json' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = 'totals-import.json';
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 5000);
  } catch (e) {
    /* no DOM (e.g. Scriptable evaluateJavaScript) — expose the string */
  }
  if (typeof window !== 'undefined') window.__totalsImportJson = json; // Scriptable can read this back
  return json;
})();
