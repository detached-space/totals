import 'dart:convert';
import 'dart:io';

void main() {
  final pJson = File('assets/sms_patterns.json').readAsStringSync();
  final patterns = ((jsonDecode(pJson) as Map<String, dynamic>)['patterns'] as List)
      .map((e) => {
            'desc': e['description'],
            'regex': e['regex'],
            'hasAccount': e['hasAccount'],
          })
      .toList();

  String fixJson(String raw) =>
      raw.replaceAll(RegExp(r',\s*}'), '}').replaceAll(RegExp(r',\s*\]'), ']');

  final all = <Map<String, dynamic>>[];
  for (final f in ['test/fixtures/unmatched-with-regex.json', 'test/fixtures/unmatched-no-regex.json']) {
    final raw = fixJson(File(f).readAsStringSync());
    all.addAll((jsonDecode(raw) as List).cast<Map<String, dynamic>>());
  }

  int noMatch = 0;
  for (final item in all) {
    final body = item['example sms'] as String;
    bool found = false;
    for (final p in patterns) {
      try {
        final re = RegExp(p['regex'] as String, caseSensitive: false, multiLine: true, dotAll: true);
        if (re.hasMatch(body)) {
          print('MATCH: ${item['title']}');
          print('   -> ${p['desc']} (hasAccount: ${p['hasAccount']})');
          found = true;
          break;
        }
      } catch (_) {}
    }
    if (!found) {
      print('NO MATCH: ${item['title']}');
      noMatch++;
    }
  }
  print('\nTotal unmatched: ${all.length}, still no match: $noMatch');
  exit(noMatch > 0 ? 1 : 0);
}
