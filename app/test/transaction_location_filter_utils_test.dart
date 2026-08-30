import 'package:flutter_test/flutter_test.dart';
import 'package:totals/utils/transaction_location_filter_utils.dart';

void main() {
  test('location filter names are trimmed, deduplicated, and ordered', () {
    final names = orderedTransactionLocationNamesForFilter(
      const <String?>[' Office ', 'home', 'office', null, ''],
    );

    expect(names, <String>['home', 'Office']);
  });

  test('location filters match transaction place names case-insensitively', () {
    final selectedNames = normalizedTransactionLocationFilterNames(
      const <String>{'HOME'},
    );
    const namesByReference = <String, String>{
      'at-home': ' Home ',
      'at-work': 'Office',
    };

    expect(
      matchesTransactionLocationFilters(
        transactionReference: 'at-home',
        locationNames: selectedNames,
        locationNameByReference: namesByReference,
      ),
      isTrue,
    );
    expect(
      matchesTransactionLocationFilters(
        transactionReference: 'at-work',
        locationNames: selectedNames,
        locationNameByReference: namesByReference,
      ),
      isFalse,
    );
    expect(
      matchesTransactionLocationFilters(
        transactionReference: 'without-location',
        locationNames: selectedNames,
        locationNameByReference: namesByReference,
      ),
      isFalse,
    );
    expect(
      matchesTransactionLocationFilters(
        transactionReference: 'without-location',
        locationNames: const <String>{},
        locationNameByReference: namesByReference,
      ),
      isTrue,
    );
  });
}
