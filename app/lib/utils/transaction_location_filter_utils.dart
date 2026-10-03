import 'package:totals/utils/account_sort.dart';

String normalizeTransactionLocationFilterName(String value) =>
    value.trim().toLowerCase();

Set<String> normalizedTransactionLocationFilterNames(
  Iterable<String> names,
) {
  return names
      .map(normalizeTransactionLocationFilterName)
      .where((name) => name.isNotEmpty)
      .toSet();
}

List<String> orderedTransactionLocationNamesForFilter(
  Iterable<String?> names,
) {
  final namesByNormalizedValue = <String, String>{};
  for (final value in names) {
    final name = value?.trim() ?? '';
    final normalizedName = normalizeTransactionLocationFilterName(name);
    if (normalizedName.isEmpty) continue;
    namesByNormalizedValue.putIfAbsent(normalizedName, () => name);
  }

  final orderedNames = namesByNormalizedValue.values.toList(growable: false)
    ..sort(compareDisplayText);
  return orderedNames;
}

bool matchesTransactionLocationFilters({
  required String transactionReference,
  required Set<String> locationNames,
  required Map<String, String> locationNameByReference,
}) {
  if (locationNames.isEmpty) return true;
  final locationName = locationNameByReference[transactionReference];
  if (locationName == null) return false;
  return locationNames.contains(
    normalizeTransactionLocationFilterName(locationName),
  );
}
