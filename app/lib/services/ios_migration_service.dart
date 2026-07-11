import 'dart:convert';
import 'dart:io';

import 'package:totals/services/data_export_import_service.dart';

/// Result of an in-app migration from the old iOS (Scriptable) Totals export.
class IosMigrationResult {
  final int transactions;
  final int categories;
  final int accounts;
  final int budgets;
  final int autoCategoryRules;
  final int contacts;
  final int syntheticReferences;
  final int unrecoveredLinks; // reference-less tx-<index> tags/overrides not in the files
  final int profilesCreated;
  final List<String> missingFiles; // expected export files not in the selection
  final List<String> warnings;

  const IosMigrationResult({
    required this.transactions,
    required this.categories,
    required this.accounts,
    required this.budgets,
    required this.autoCategoryRules,
    required this.contacts,
    required this.syntheticReferences,
    required this.unrecoveredLinks,
    required this.profilesCreated,
    required this.missingFiles,
    required this.warnings,
  });
}

/// Converts an old iOS-workaround export (JSONL files) into the app's schema-v8
/// import payload and imports it via [DataExportImportService.importAllData].
///
/// The user points the app at their old export folder; this reads the files,
/// maps them, and migrates — no external tooling. Mirrors `app/migration/` JS.
///
/// Fidelity: transactions with no bank `reference` were keyed in the old app by a
/// synthetic `tx-<index>` id that isn't stored in the files, so category tags /
/// account overrides that reference such an id can't be re-attached (counted in
/// [IosMigrationResult.unrecoveredLinks]). Everything else migrates.
class IosMigrationService {
  IosMigrationService._();
  static final IosMigrationService instance = IosMigrationService._();

  static const String sourceType = 'ios_migration';

  static const _fileNames = <String>[
    'transactions.txt',
    'categories.txt',
    'reasons.txt',
    'account_overrides.txt',
    'custom_categories.txt',
    'category_rules.txt',
    'accounts.txt',
    'contacts.txt',
    'profiles.txt',
    'budgets.txt',
    'failed_parsings.txt',
    'banks.json',
  ];

  // Fallback bank masking config (id -> [maskPattern, uniformMasking]) when the
  // export doesn't include banks.json. Matches the app's bundled bank list.
  static const Map<int, List<Object>> _bankFallback = {
    1: [3, true], 2: [0, false], 3: [2, true], 4: [3, true], 5: [4, true],
    6: [0, false], 7: [4, true], 8: [0, false], 9: [3, true], 10: [4, true],
    12: [2, true], 19: [3, true], 36: [2, true], 37: [0, false],
  };

  /// Reads the known export files from [dir]. Returns null if the folder doesn't
  /// look like an old export (no transactions.txt).
  Future<Map<String, String>?> readExportDirectory(String dir) async {
    final txPath = '$dir/transactions.txt';
    if (!await File(txPath).exists()) return null;
    final out = <String, String>{};
    for (final name in _fileNames) {
      final f = File('$dir/$name');
      if (await f.exists()) {
        try {
          out[name] = await f.readAsString();
        } catch (_) {/* skip unreadable */}
      }
    }
    return out;
  }

  /// Full migration: convert [files] (name -> contents) and import. Returns stats.
  Future<IosMigrationResult> importFromFiles(Map<String, String> files) async {
    final built = _buildImportPayload(files);
    await DataExportImportService().importAllData(jsonEncode(built.payload));
    return built.result;
  }

  /// Convert only (no import) — the schema-v8 payload plus stats. For preview/tests.
  ({Map<String, dynamic> payload, IosMigrationResult result}) convert(
      Map<String, String> files) {
    final built = _buildImportPayload(files);
    return (payload: built.payload, result: built.result);
  }

  // ---- conversion ----------------------------------------------------------

  List<Map<String, dynamic>> _jsonl(Map<String, String> files, String name) {
    final raw = files[name];
    if (raw == null) return const [];
    final out = <Map<String, dynamic>>[];
    for (final line in const LineSplitter().convert(raw)) {
      final s = line.trim();
      if (s.isEmpty) continue;
      try {
        final v = jsonDecode(s);
        if (v is Map<String, dynamic>) out.add(v);
      } catch (_) {/* skip malformed line */}
    }
    return out;
  }

  String _s(dynamic v) => v == null ? '' : v.toString().trim();

  String _normCounterparty(dynamic v) =>
      _s(v).replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  String? _last4(dynamic acct) {
    final s = _s(acct);
    if (s.isEmpty) return null;
    // Masked accounts (e.g. "99*******3776", "5079******031") — the true suffix is the
    // digits after the last mask char, not the last 4 of the whole string (which would
    // wrongly borrow digits from the visible prefix). Fall back to last-4 of all digits.
    final star = s.lastIndexOf('*');
    final tail = star >= 0 ? s.substring(star + 1) : s;
    var digits = tail.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return digits.length <= 4 ? digits : digits.substring(digits.length - 4);
  }

  /// Parses an amount/balance the way the old app did: strips thousands commas,
  /// currency text and trailing junk (e.g. "1,000" → 1000, "833.16." → 833.16),
  /// tolerating both numeric and string inputs. Returns null for empty/unparseable.
  double? _parseAmount(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    var s = v.toString().trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'[^0-9.]'), ''); // drop commas, currency, trailing chars
    final firstDot = s.indexOf('.');
    if (firstDot != -1) {
      s = s.substring(0, firstDot + 1) + s.substring(firstDot + 1).replaceAll('.', '');
    }
    if (s.endsWith('.')) s += '0';
    if (s.isEmpty || s == '.') return null;
    return double.tryParse(s);
  }

  String? _toIso(dynamic ts) {
    final s = _s(ts);
    if (s.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) return s;
    final d = DateTime.tryParse(s);
    return d?.toUtc().toIso8601String();
  }

  num? _numOrNull(dynamic v) {
    if (v == null || v == '') return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  // FNV-1a → base36, for stable synthetic references on reference-less rows.
  String _fnv1a(String str) {
    var h = 0x811c9dc5;
    for (var i = 0; i < str.length; i++) {
      h ^= str.codeUnitAt(i);
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(36);
  }

  String _syntheticReference(Map<String, dynamic> tx) {
    final key = [tx['amount'], tx['timestamp'], tx['bankId'], tx['balance'], tx['type'], tx['account']]
        .map(_s)
        .join('|');
    return 'iosmig-${_fnv1a(key)}';
  }

  // bankId -> {mask:int, uniform:bool}, from banks.json if present else fallback.
  Map<int, ({int mask, bool uniform})> _bankInfo(Map<String, String> files) {
    final info = <int, ({int mask, bool uniform})>{};
    final raw = files['banks.json'];
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        final list = (decoded is Map ? decoded['banks'] : decoded) as List;
        for (final b in list) {
          final id = _numOrNull(b['id'])?.toInt();
          if (id == null) continue;
          info[id] = (
            mask: _numOrNull(b['maskPattern'])?.toInt() ?? 4,
            uniform: b['uniformMasking'] == true,
          );
        }
      } catch (_) {/* fall through to fallback */}
    }
    _bankFallback.forEach((id, v) {
      info.putIfAbsent(id, () => (mask: v[0] as int, uniform: v[1] as bool));
    });
    return info;
  }

  String _digitsOf(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Accounts whose full number fits a masked SMS account string's visible
  /// prefix+suffix ("01320xxxxxx2500", "99*******3508") — or equals it when
  /// unmasked. Masks with under 4 visible digits are treated as no signal.
  /// This outperforms the old app (override→default only) for non-uniform
  /// banks like Awash and never contradicted the user's manual overrides in
  /// the real dataset.
  List<Map<String, dynamic>> _maskedHits(
      String masked, List<Map<String, dynamic>> accts) {
    final s = masked.trim();
    if (s.isEmpty) return const [];
    final m = RegExp(r'^(\d*)[xX*]+(\d*)$').firstMatch(s);
    if (m != null) {
      final pre = m.group(1)!, suf = m.group(2)!;
      if (pre.length + suf.length < 4) return const [];
      return accts.where((a) {
        final n = _digitsOf(_s(a['number']));
        return n.startsWith(pre) && n.endsWith(suf);
      }).toList();
    }
    final d = _digitsOf(s);
    if (d.isEmpty) return const [];
    return accts.where((a) => _digitsOf(_s(a['number'])) == d).toList();
  }

  /// Reconstructs each account's balance from its transactions (the old app never
  /// persists balances; iOS has no SMS parser to maintain them). Assigns each
  /// transaction to an account by: account override → uniform-mask last-N match →
  /// the bank's default account; then takes the latest transaction's balance-after.
  Map<String, double> _computeAccountBalances(
    List<Map<String, dynamic>> rawTxs,
    List<Map<String, dynamic>> accounts,
    Map<String, Map<String, dynamic>> overridesByTxId,
    Map<int, ({int mask, bool uniform})> bankInfo,
  ) {
    final byBank = <int, List<Map<String, dynamic>>>{};
    for (final a in accounts) {
      final bid = _numOrNull(a['bankId'])?.toInt();
      if (bid != null) byBank.putIfAbsent(bid, () => []).add(a);
    }
    Map<String, dynamic>? defaultAcct(int bid) {
      final lst = byBank[bid] ?? const [];
      for (final a in lst) {
        if (a['isDefault'] == true) return a;
      }
      return lst.isNotEmpty ? lst.first : null;
    }

    Map<String, dynamic>? maskedMatch(
        String masked, List<Map<String, dynamic>> accts) {
      final hits = _maskedHits(masked, accts);
      return hits.length == 1 ? hits.first : null; // ambiguous → no match
    }

    final perAccount = <String, List<(DateTime?, double)>>{};
    for (final t in rawTxs) {
      final bid = _numOrNull(t['bankId'])?.toInt();
      if (bid == null) continue;
      final ref = _s(t['reference']);
      Map<String, dynamic>? acct;
      if (ref.isNotEmpty && overridesByTxId.containsKey(ref)) {
        final num = _s(overridesByTxId[ref]!['accountNumber']);
        for (final a in byBank[bid] ?? const []) {
          if (_s(a['number']) == num) {
            acct = a;
            break;
          }
        }
      }
      if (acct == null) {
        final info = bankInfo[bid];
        if (info != null && info.uniform) {
          final mp = info.mask == 0 ? 4 : info.mask;
          final tacc = _digitsOf(_s(t['account']));
          if (tacc.length >= mp) {
            for (final a in byBank[bid] ?? const []) {
              final anum = _digitsOf(_s(a['number']));
              if (anum.length >= mp &&
                  tacc.substring(tacc.length - mp) == anum.substring(anum.length - mp)) {
                acct = a;
                break;
              }
            }
          }
        } else {
          // Non-uniform bank (e.g. Awash): try the masked account string
          // before falling back to the bank's default account.
          acct = maskedMatch(_s(t['account']), byBank[bid] ?? const []) ??
              defaultAcct(bid);
        }
      }
      if (acct == null) continue;
      // Stamp the resolved account on the tx so profile assignment can reuse it.
      t['__acct'] = _s(acct['number']);
      final bal = _parseAmount(t['balance']);
      if (bal == null) continue;
      perAccount
          .putIfAbsent(_s(acct['number']), () => [])
          .add((DateTime.tryParse(_s(t['timestamp'])), bal));
    }

    final out = <String, double>{};
    perAccount.forEach((num, list) {
      list.sort((a, b) =>
          (a.$1 ?? DateTime(0)).compareTo(b.$1 ?? DateTime(0)));
      out[num] = list.last.$2;
    });
    return out;
  }

  _Built _buildImportPayload(Map<String, String> files) {
    final transactions = _jsonl(files, 'transactions.txt');
    final categoriesFile = _jsonl(files, 'categories.txt');
    final reasonsFile = _jsonl(files, 'reasons.txt');
    final overridesFile = _jsonl(files, 'account_overrides.txt');
    final customCategories = _jsonl(files, 'custom_categories.txt');
    final categoryRules = _jsonl(files, 'category_rules.txt');
    final accounts = _jsonl(files, 'accounts.txt');
    final contacts = _jsonl(files, 'contacts.txt');
    final profiles = _jsonl(files, 'profiles.txt');
    final budgetsFile = _jsonl(files, 'budgets.txt');
    final failedParsings = _jsonl(files, 'failed_parsings.txt');

    // Each transaction's txId: `.id` if the export carries it (lossless), else the
    // bank reference. Reference-less rows can't be matched.
    final byTxId = <String, Map<String, dynamic>>{};
    for (final tx in transactions) {
      final id = _s(tx['id']).isNotEmpty ? _s(tx['id']) : _s(tx['reference']);
      tx['__txId'] = id.isEmpty ? null : id;
      if (id.isNotEmpty) byTxId.putIfAbsent(id, () => tx);
    }

    int catUnrecovered = 0, overrideUnrecovered = 0, reasonUnrecovered = 0;
    final manualCats = <String, List<String>>{};
    for (final c in categoriesFile) {
      final id = _s(c['txId']);
      if (!byTxId.containsKey(id)) {
        catUnrecovered++;
        continue;
      }
      manualCats[id] = (c['categories'] as List?)?.map((e) => e.toString()).toList() ?? [];
    }
    final reasons = <String, String>{};
    for (final r in reasonsFile) {
      final id = _s(r['txId']);
      if (!byTxId.containsKey(id)) {
        reasonUnrecovered++;
        continue;
      }
      reasons[id] = _s(r['reason']);
    }
    final overrides = <String, Map<String, dynamic>>{};
    for (final o in overridesFile) {
      final id = _s(o['txId']);
      if (!byTxId.containsKey(id)) {
        overrideUnrecovered++;
        continue;
      }
      overrides[id] = {'accountNumber': o['accountNumber'], 'bankId': o['bankId']};
    }

    final rulesByReceiver = <String, List<String>>{};
    for (final r in categoryRules) {
      final k = _s(r['receiver']).toLowerCase();
      if (k.isEmpty) continue;
      (rulesByReceiver[k] ??= []).add(_s(r['category']));
    }

    final acctToProfileIdx = <String, int>{};
    for (var i = 0; i < profiles.length; i++) {
      for (final n in (profiles[i]['accounts'] as List? ?? const [])) {
        acctToProfileIdx[_s(n)] = i;
      }
    }

    // Assign each transaction to an account (stamps `__acct`) and reconstruct
    // per-account balances. Done before the tx loop so profile tagging can reuse
    // the same account assignment (override → mask match → default).
    final warnings = <String>[];

    // Repair rows the old parser filed under the wrong bank (e.g. Amhara debit
    // alerts stored as CBE credits): when the masked account matches NO account
    // of the claimed bank but exactly ONE account overall, the mask wins — it is
    // the bank naming the account.
    var rebanked = 0;
    for (final t in transactions) {
      final bid = _numOrNull(t['bankId'])?.toInt();
      final own = accounts
          .where((a) => _numOrNull(a['bankId'])?.toInt() == bid)
          .toList();
      if (_maskedHits(_s(t['account']), own).isNotEmpty) continue;
      final global = _maskedHits(_s(t['account']), accounts);
      if (global.length == 1) {
        t['bankId'] = _numOrNull(global.first['bankId'])?.toInt();
        t['__rebanked'] = true;
        rebanked++;
      }
    }

    final bankInfo = _bankInfo(files);
    final accountBalances =
        _computeAccountBalances(transactions, accounts, overrides, bankInfo);

    // Direction repair for re-banked rows: the target account's balance chain
    // proves DEBIT/CREDIT where consecutive balances line up (prev − amt == bal
    // or prev + amt == bal). Rows the chain can't prove keep their stored type
    // and are flagged for review in their note — never silently guessed.
    var retyped = 0, flaggedForReview = 0;
    if (rebanked > 0) {
      final byAcct = <String, List<Map<String, dynamic>>>{};
      for (final t in transactions) {
        final a = _s(t['__acct']);
        if (a.isNotEmpty) byAcct.putIfAbsent(a, () => []).add(t);
      }
      for (final t in transactions) {
        if (t['__rebanked'] != true) continue;
        final rows = byAcct[_s(t['__acct'])] ?? const [];
        final amt = _parseAmount(t['amount']);
        final bal = _parseAmount(t['balance']);
        final ts = DateTime.tryParse(_s(t['timestamp']));
        String? proven;
        if (amt != null && bal != null && ts != null) {
          final earlier = <(DateTime, double)>[];
          for (final r in rows) {
            if (identical(r, t)) continue;
            final rts = DateTime.tryParse(_s(r['timestamp']));
            final rbal = _parseAmount(r['balance']);
            if (rts != null && rbal != null && rts.isBefore(ts)) {
              earlier.add((rts, rbal));
            }
          }
          earlier.sort((a, b) => b.$1.compareTo(a.$1)); // nearest first
          for (final e in earlier.take(3)) {
            if ((e.$2 - amt - bal).abs() <= 0.02) {
              proven = 'DEBIT';
              break;
            }
            if ((e.$2 + amt - bal).abs() <= 0.02) {
              proven = 'CREDIT';
              break;
            }
          }
        }
        if (proven != null) {
          if (proven != _s(t['type']).toUpperCase()) retyped++;
          t['__fixedType'] = proven;
        } else {
          t['__suspect'] = true;
          flaggedForReview++;
        }
      }
      warnings.add(
          '$rebanked mis-banked row(s) re-filed by account mask; $retyped direction-corrected; $flaggedForReview flagged for review (see transaction notes)');
    }

    // Resolve each transaction (manual tags override rule tags, like the old app).
    final resolvedTxs = transactions.map((tx) {
      final txId = tx['__txId'] as String?;
      List<String> categories = [];
      if (txId != null && manualCats.containsKey(txId)) {
        categories = manualCats[txId]!;
      } else {
        final rk = _s(tx['receiver']).toLowerCase();
        if (rk.isNotEmpty && rulesByReceiver.containsKey(rk)) {
          categories = List<String>.from(rulesByReceiver[rk]!);
        }
      }
      final override = (txId != null) ? overrides[txId] : null;
      // Profile follows the account the tx resolves to (override/mask/default).
      final profileNumber = acctToProfileIdx[_s(tx['__acct'])];
      // 454 rows in real exports carry no `type` (deposits especially). The old
      // app classified those by heuristic (totals.js:30764): has a receiver →
      // expense, none → deposit. Passing null instead makes the new app count
      // them in neither credits nor debits and render deposits as expenses.
      // Chain-proven corrections (re-banked rows) take precedence over both.
      var type = _s(tx['__fixedType']).isNotEmpty
          ? _s(tx['__fixedType'])
          : _s(tx['type']).toUpperCase();
      if (type.isEmpty) {
        final recv = _s(tx['receiver']);
        type = (recv.isNotEmpty && recv.toLowerCase() != 'unknown')
            ? 'DEBIT'
            : 'CREDIT';
      }
      final baseReason = (txId != null) ? _s(reasons[txId]) : '';
      final noteParts = <String>[
        if (baseReason.isNotEmpty) baseReason,
        if (tx['__suspect'] == true)
          'Review: bank auto-corrected from old export; direction unverified',
      ];
      return {
        'amount': tx['amount'],
        'reference': tx['reference'],
        'account': override != null ? override['accountNumber'] : tx['account'],
        'receiver': tx['receiver'],
        'vat': tx['vat'],
        'serviceCharge': tx['serviceCharge'],
        'balance': tx['balance'],
        'bankId': tx['bankId'],
        'type': type,
        'timestamp': tx['timestamp'],
        'categories': categories,
        'reason': noteParts.isEmpty ? null : noteParts.join(' — '),
        'profileNumber': profileNumber,
      };
    }).toList();

    // --- category flow inference (majority credit->income) + registry ---
    final customByName = <String, Map<String, dynamic>>{};
    for (final c in customCategories) {
      customByName[_s(c['name']).toLowerCase()] = c;
    }
    final usage = <String, List<int>>{}; // name -> [credit, debit]
    for (final tx in resolvedTxs) {
      final isCredit = _s(tx['type']).toUpperCase() == 'CREDIT';
      for (final cn in (tx['categories'] as List)) {
        final k = _s(cn).toLowerCase();
        final u = usage.putIfAbsent(k, () => [0, 0]);
        u[isCredit ? 0 : 1]++;
      }
    }
    String flowFor(String name) {
      final k = _s(name).toLowerCase();
      final custom = customByName[k];
      final t = custom == null ? null : _s(custom['type']);
      if (t == 'income') return 'income';
      if (t == 'expense') return 'expense';
      final u = usage[k];
      if (u != null && (u[0] + u[1]) > 0) return u[0] > u[1] ? 'income' : 'expense';
      return 'expense';
    }

    final catId = <String, int>{}; // name|flow -> id
    final categories = <Map<String, dynamic>>[];
    var nextCatId = 1;
    int? registerCategory(String? name, [String? flowOverride]) {
      final nm = _s(name);
      if (nm.isEmpty) return null;
      final flow = flowOverride ?? flowFor(nm);
      final key = '${nm.toLowerCase()}|$flow';
      if (catId.containsKey(key)) return catId[key];
      final id = nextCatId++;
      catId[key] = id;
      final custom = customByName[nm.toLowerCase()];
      categories.add({
        'id': id,
        'name': nm,
        'flow': flow,
        'colorKey': custom != null && _s(custom['color']).isNotEmpty ? custom['color'] : null,
        'essential': false,
        'uncategorized': false,
        'recurring': false,
        'builtIn': false,
      });
      return id;
    }
    for (final c in customCategories) {
      final t = _s(c['type']);
      if (t == 'both') warnings.add('custom category "${_s(c['name'])}" is type "both"; imported as expense');
      registerCategory(_s(c['name']), t == 'income' ? 'income' : 'expense');
    }

    // --- transactions ---
    final usedRefs = <String>{};
    var synthRefs = 0, dupSuffix = 0;
    final outTransactions = resolvedTxs.map((tx) {
      var reference = _s(tx['reference']);
      if (reference.isEmpty) {
        reference = _syntheticReference(tx);
        synthRefs++;
      }
      var ref = reference;
      while (usedRefs.contains(ref)) {
        ref = '$reference-${++dupSuffix}';
      }
      usedRefs.add(ref);

      final catIds = <int>[];
      for (final cn in (tx['categories'] as List)) {
        final id = registerCategory(cn.toString());
        if (id != null) catIds.add(id);
      }
      final receiver = _s(tx['receiver']);
      final bal = _parseAmount(tx['balance']);
      return {
        'amount': (_parseAmount(tx['amount']) ?? 0),
        'reference': ref,
        'receiver': receiver.isNotEmpty && receiver.toLowerCase() != 'unknown' ? receiver : null,
        'note': _s(tx['reason']).isNotEmpty ? _s(tx['reason']) : null,
        'time': _toIso(tx['timestamp']),
        'currentBalance': bal == null ? null : bal.toString(),
        'bankId': _numOrNull(tx['bankId']),
        'type': _s(tx['type']).toUpperCase().isNotEmpty ? _s(tx['type']).toUpperCase() : null,
        'accountNumber': _last4(tx['account']),
        'categoryIds': catIds.isNotEmpty ? catIds : null,
        'categoryId': catIds.isNotEmpty ? catIds.first : null,
        'serviceCharge': _parseAmount(tx['serviceCharge']),
        'vat': _parseAmount(tx['vat']),
        'sourceType': sourceType,
        // profile index the tx belongs to (via its resolved account); the
        // importer maps it to a real profileId. null → default profile.
        'profileNumber': tx['profileNumber'],
      };
    }).toList();

    // --- accounts (balances + profile membership computed above) ---
    final outAccounts = accounts
        .map((a) => {
              'accountNumber': _s(a['number']),
              'bank': _numOrNull(a['bankId']),
              'balance': accountBalances[_s(a['number'])] ?? 0,
              'accountHolderName': _s(a['name']).isNotEmpty ? _s(a['name']) : _s(a['number']),
              'profileNumber': acctToProfileIdx[_s(a['number'])],
            })
        .where((a) => (a['accountNumber'] as String).isNotEmpty && a['bank'] != null)
        .toList();

    // --- userAccounts <- contacts ---
    final outUserAccounts = contacts
        .map((c) => {
              'accountNumber': _s(c['number']),
              'bankId': _numOrNull(c['bankId']),
              'accountHolderName': _s(c['name']).isNotEmpty ? _s(c['name']) : _s(c['number']),
              'createdAt': _toIso(c['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
            })
        .where((c) => (c['accountNumber'] as String).isNotEmpty && c['bankId'] != null)
        .toList();

    // --- auto-category rules ---
    final outRules = <Map<String, dynamic>>[];
    final seenRule = <String>{};
    var ruleCollisions = 0;
    for (final r in categoryRules) {
      final flow = flowFor(_s(r['category']));
      final id = registerCategory(_s(r['category']));
      if (id == null) continue;
      final norm = _normCounterparty(r['receiver']);
      if (norm.isEmpty) continue;
      final key = '$norm|$flow';
      if (seenRule.contains(key)) ruleCollisions++;
      seenRule.add(key);
      outRules.add({
        'counterparty': _s(r['receiver']),
        'normalizedCounterparty': norm,
        'flow': flow,
        'categoryId': id,
        'isPrimary': true,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    }
    if (ruleCollisions > 0) {
      warnings.add('$ruleCollisions auto-category rule(s) collapsed (one category per receiver+flow)');
    }

    // --- budgets (approximate) ---
    final budgetGroups = budgetsFile.where((b) => b['type'] == 'group').toList();
    final budgetItems = budgetsFile.where((b) => b['type'] == 'budget').toList();
    final outBudgets = budgetItems.map((b) {
      final cids = <int>[];
      for (final n in (b['categories'] as List? ?? const [])) {
        final id = registerCategory(n.toString());
        if (id != null) cids.add(id);
      }
      final month = _s(b['month']);
      final start = month.isNotEmpty
          ? '$month-01T00:00:00.000Z'
          : (_toIso(b['createdAt']) ?? DateTime.now().toUtc().toIso8601String());
      return {
        'name': _s(b['name']),
        'type': 'category',
        'amount': (_parseAmount(b['assigned']) ?? 0),
        'categoryIds': cids.isNotEmpty ? cids : null,
        'categoryId': cids.isNotEmpty ? cids.first : null,
        'startDate': start,
        'timeFrame': (b['recurring'] == true) ? 'monthly' : 'never',
        'isActive': true,
        'rollover': false,
        'alertThreshold': 80.0,
        'createdAt': _toIso(b['createdAt']) ?? DateTime.now().toUtc().toIso8601String(),
        'calendar': 'gregorian',
      };
    }).toList();
    if (budgetGroups.isNotEmpty) {
      warnings.add('budget groups (${budgetGroups.map((g) => _s(g['name'])).join(', ')}) are not represented in the app');
    }

    // --- failed parses ---
    final outFailed = failedParsings
        .where((f) => _s(f['message']).isNotEmpty)
        .map((f) => {
              'address': '',
              'body': _s(f['message']),
              'reason': 'imported from iOS workaround',
              'timestamp': _toIso(f['timestamp']) ?? DateTime.now().toUtc().toIso8601String(),
            })
        .toList();

    // --- profiles (non-standard section; consumed by the importer) ---
    final outProfiles = <Map<String, dynamic>>[];
    for (var i = 0; i < profiles.length; i++) {
      final p = profiles[i];
      outProfiles.add({
        'index': i,
        'name': _s(p['name']).isNotEmpty ? _s(p['name']) : 'Profile ${i + 1}',
        'order': _numOrNull(p['order'])?.toInt() ?? i,
      });
    }

    final payload = <String, dynamic>{
      'schemaVersion': 8,
      'version': '1.0',
      'exportDate': DateTime.now().toUtc().toIso8601String(),
      'migratedFrom': 'totals-ios-scriptable',
      'categories': categories,
      'accounts': outAccounts,
      'userAccounts': outUserAccounts,
      'transactions': outTransactions,
      'budgets': outBudgets,
      'autoCategoryRules': outRules,
      'failedParses': outFailed,
      if (outProfiles.isNotEmpty) 'profiles': outProfiles,
    };

    // Which important export files were NOT provided in the selection. Missing
    // ones silently degrade the migration (e.g. no profiles.txt → no profiles,
    // no account_overrides.txt → wrong multi-account split), so surface them.
    const importantFiles = <String>[
      'transactions.txt',
      'accounts.txt',
      'account_overrides.txt',
      'profiles.txt',
      'categories.txt',
      'custom_categories.txt',
      'category_rules.txt',
      'reasons.txt',
      'budgets.txt',
      'banks.json',
    ];
    final missingFiles =
        importantFiles.where((f) => !files.containsKey(f)).toList();

    final result = IosMigrationResult(
      transactions: outTransactions.length,
      categories: categories.length,
      accounts: outAccounts.length,
      budgets: outBudgets.length,
      autoCategoryRules: outRules.length,
      contacts: outUserAccounts.length,
      syntheticReferences: synthRefs,
      unrecoveredLinks: catUnrecovered + overrideUnrecovered + reasonUnrecovered,
      profilesCreated: outProfiles.length,
      missingFiles: missingFiles,
      warnings: warnings,
    );

    return _Built(payload, result);
  }
}

class _Built {
  final Map<String, dynamic> payload;
  final IosMigrationResult result;
  _Built(this.payload, this.result);
}
