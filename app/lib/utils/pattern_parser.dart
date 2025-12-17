import 'package:totals/models/sms_pattern.dart';

class PatternParser {
  /// Iterates through [patterns] that match the [senderAddress].
  /// Returns a map of extracted data if a match is found, or null otherwise.
  static Map<String, dynamic>? extractTransactionDetails(
      String messageBody, String senderAddress, List<SmsPattern> patterns) {
    String cleanBody = messageBody.trim();

    for (var pattern in patterns) {
      print("debug: Pattern Regex: ${[pattern.bankId]} ${pattern.regex}");

      // 2. Try to match regex
      try {
        RegExp regExp = RegExp(pattern.regex,
            caseSensitive: false, multiLine: true, dotAll: true);
        RegExpMatch? match = regExp.firstMatch(cleanBody);

        if (match != null) {
          print("debug: ✓ Pattern Matched: ${pattern.description}");
          print("debug: Available named groups: ${match.groupNames.toList()}");

          final Map<String, dynamic> extracted = {};

          // Extract known named groups
          // We support: amount, balance, account, reference, creditor, time

          extracted['type'] = pattern.type;
          extracted['bankId'] = pattern.bankId; // Default bank ID from pattern

          if (match.groupNames.contains('amount')) {
            print("debug: Extracted amount: ${match.namedGroup('amount')}");
            extracted['amount'] =
                double.tryParse(_cleanNumber(match.namedGroup('amount')) ?? "");
            print("debug: Extracted amount: ${extracted['amount']}");
          }
          if (match.groupNames.contains('balance')) {
            extracted['currentBalance'] =
                _cleanNumber(match.namedGroup('balance'));
            print("debug: Extracted balance: ${extracted['currentBalance']}");
          }
          if (match.groupNames.contains('account')) {
            print("debug: ✓ after account - entering account extraction block");
            String? raw = match.namedGroup('account');
            print("debug: Raw account value: '$raw'");

            if (raw != null) {
              // specific cleanup for masked accounts (CBE style 1000***1234)
              if (pattern.bankId == 1) {
                extracted['accountNumber'] = raw.substring(raw.length - 4);
                print(
                    "Cleaned account (masked): ${extracted['accountNumber']}");
              }
              if (pattern.bankId == 3) {
                extracted['accountNumber'] = raw.substring(raw.length - 2);
                print(
                    "Cleaned account (masked): ${extracted['accountNumber']}");
              }
              if (pattern.bankId == 4) {
                extracted['accountNumber'] = raw.substring(raw.length - 3);
                print(
                    "Cleaned account (masked): ${extracted['accountNumber']}");
              } else {
                extracted['accountNumber'] = raw;
                print(
                    "Cleaned account (direct): ${extracted['accountNumber']}");
              }
            } else {
              print("debug: ✗ Raw account is null!");
            }
          } else {
            print("debug: ✗ 'account' group NOT found in named groups");
          }

          if (match.groupNames.contains('reference')) {
            extracted['reference'] = match.namedGroup('reference');
            print("debug: Extracted reference: ${extracted['reference']}");
          }
          if (match.groupNames.contains('creditor')) {
            extracted['creditor'] = match.namedGroup('creditor');
          }
          if (match.groupNames.contains("receiver")) {
            extracted['receiver'] = match.namedGroup('receiver');
          }
          if (match.groupNames.contains('time')) {
            // Date parsing is complex, for now store raw string or try basic parse
            // Ideally the regex extracts ISO-like or we have a date parser helper
            extracted['raw_time'] = match.namedGroup('time');
            extracted['time'] = DateTime.now()
                .toIso8601String(); // Default to now if parse fails
          } else {
            extracted['time'] = DateTime.now().toIso8601String();
          }

          print("debug: account ${extracted["accountNumber"]}");
          print("debug: amount ${extracted["amount"]}");
          print("debug: balance ${extracted["currentBalance"]}");
          print("debug: reference ${extracted["reference"]}");
          print("debug: receiver ${extracted["receiver"]}");

          if ((pattern.bankId == 4 || pattern.bankId == 2) &&
              extracted["reference"] == null) {
            extracted["reference"] = DateTime.now().toIso8601String();
          }
          // Validate required fields
          if ((pattern.bankId == 1 ||
                  pattern.bankId == 3 ||
                  pattern.bankId == 4) &&
              (extracted['amount'] == null ||
                  extracted['currentBalance'] == null ||
                  extracted['accountNumber'] == null ||
                  extracted['reference'] == null)) {
            print(
                "✗ Pattern '${pattern.description}' matched but missing required fields (amount, balance, or reference). Skipping.");
            continue;
          }

          print(
              "dubg: ✓ All required fields present. Returning extracted data.");
          return extracted;
        } else {
          print("debug: ✗ No match for pattern: ${pattern.description}");
        }
      } catch (e) {
        print("debug: ✗ Error checking pattern '${pattern.description}': $e");
        // Continue to next pattern
      }
    }

    print("debug: \n✗ No matching pattern found for message.");
    return null; // No match found
  }

  static String? _cleanNumber(String? input) {
    if (input == null) return null;

    String cleaned = input.replaceAll(',', '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'[^0-9.]$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\.+$'), '');

    return cleaned;
  }
}
