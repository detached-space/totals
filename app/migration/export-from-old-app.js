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
