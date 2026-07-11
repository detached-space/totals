import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:totals/services/ios_migration_service.dart';

/// Validates the in-app Dart converter against the real exported ios-files/,
/// mirroring the numbers proven by the JS reference converter in app/migration/.
void main() {
  const exportDir = '/Users/yewe/W/totals/totals-staging/ios-files';

  test('converts the real iOS export to a schema-v8 payload', () async {
    final dir = Directory(exportDir);
    if (!dir.existsSync()) {
      // The sample export isn't present in this checkout; skip rather than fail.
      return;
    }
    final files = <String, String>{};
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (name.endsWith('.txt') || name.endsWith('.json')) {
        files[name] = f.readAsStringSync();
      }
    }

    final out = IosMigrationService.instance.convert(files);
    final r = out.result;
    final p = out.payload;

    // Matches the validated JS converter output.
    expect(r.transactions, 2199);
    expect(r.syntheticReferences, 736);
    expect(r.unrecoveredLinks, 48); // 37 category + 11 override (reference-less tx-<index>)
    expect(r.categories, 25);
    expect(r.accounts, 13);
    expect(r.contacts, 6);
    expect(r.autoCategoryRules, 26);
    expect(r.budgets, 2);

    // Schema shape.
    expect(p['schemaVersion'], 8);
    final txs = (p['transactions'] as List).cast<Map<String, dynamic>>();
    expect(txs.length, 2199);
    // Every transaction has a non-empty, unique reference (import requires it).
    final refs = txs.map((t) => t['reference'] as String).toList();
    expect(refs.where((r) => r.isEmpty), isEmpty);
    expect(refs.toSet().length, refs.length);
    // Reference-less rows got synthetic refs.
    expect(refs.where((r) => r.startsWith('iosmig-')).length, greaterThanOrEqualTo(736));
    // Notes and categories are attached: 28 user reasons + 5 review flags on
    // re-banked rows whose direction the balance chain couldn't prove.
    expect(txs.where((t) => t['note'] != null).length, 33);
    expect(txs.where((t) => t['categoryIds'] != null).length, greaterThan(100));

    // No amount should be 0 unless the source was genuinely empty/zero — guards the
    // comma/trailing-period parsing bug ("1,000" and "833.16." must not become 0/null).
    final zeroAmounts = txs.where((t) => (t['amount'] as num) == 0).length;
    expect(zeroAmounts, lessThan(10), reason: 'string amounts like "1,000" must parse');
    // Balances present on nearly all rows (was 152 null before the fix).
    final nullBalances = txs.where((t) => t['currentBalance'] == null).length;
    expect(nullBalances, lessThan(60), reason: 'string balances like "833.16." must parse');

    // Account balances are reconstructed from transactions (was all 0 before).
    final accts = (p['accounts'] as List).cast<Map<String, dynamic>>();
    final nonZero = accts.where((a) => (a['balance'] as num) != 0).length;
    expect(nonZero, greaterThan(8), reason: 'multi-account bank balances must not be 0');
    final total = accts.fold<double>(0, (s, a) => s + (a['balance'] as num));
    // Old app total was ~376K; reconstruction should be in the right ballpark.
    expect(total, greaterThan(300000));
    expect(total, lessThan(450000));

    // Profiles are emitted, and accounts/transactions carry a profileNumber.
    final profiles = (p['profiles'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    expect(profiles.length, 2, reason: 'Yew + Synergy');
    expect(profiles.map((pr) => pr['name']).toSet(), {'Yew', 'Synergy'});

    // The two Awash accounts (9200 / 2500) must land in DIFFERENT profiles — this
    // is what fixes the duplicate-data bug (each profile then has one Awash acct).
    final awash = accts.where((a) => a['bank'] == 2).toList();
    expect(awash.length, 2);
    final awashProfiles = awash.map((a) => a['profileNumber']).toSet();
    expect(awashProfiles.length, 2, reason: 'Awash accounts split across profiles');

    // Transactions carry a profileNumber, and most resolve to a profile.
    final tagged = txs.where((t) => t['profileNumber'] != null).length;
    expect(tagged, greaterThan(txs.length ~/ 2));
  });
}
