import 'package:totals/models/sms_pattern.dart';
import 'package:totals/services/bank_config_service.dart';

class PatternParser {
  /// Iterates through [patterns] that match the [senderAddress].
  /// Returns a map of extracted data if a match is found, or null otherwise.
  static Future<Map<String, dynamic>?> extractTransactionDetails(
      String messageBody,
      String senderAddress,
      DateTime? messageDate,
      List<SmsPattern> patterns) async {
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
            final cleanedAmount = _cleanNumber(match.namedGroup('amount'));
            extracted['amount'] = double.tryParse(cleanedAmount ?? "");
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
              final BankConfigService bankConfigService = BankConfigService();
              final banks = await bankConfigService.getBanks();
              final bank = banks.firstWhere((b) => b.id == pattern.bankId);

              // Use bank configuration for account extraction
              if (bank.uniformMasking == true && bank.maskPattern != null) {
                // Extract last N digits based on mask pattern
                if (raw.length >= bank.maskPattern!) {
                  extracted['accountNumber'] =
                      raw.substring(raw.length - bank.maskPattern!);
                  print(
                      "Cleaned account (masked): ${extracted['accountNumber']}");
                } else {
                  extracted['accountNumber'] = raw;
                  print(
                      "Cleaned account (fallback): ${extracted['accountNumber']}");
                }
              } else {
                // No masking or uniformMasking is false - use full account number
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
          if (match.groupNames.contains('type')) {
            final rawType = match.namedGroup('type');
            final normalized = _normalizeType(rawType);
            if (normalized != null) {
              extracted['type'] = normalized;
            }
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

          if (pattern.refRequired == false && extracted["reference"] == null) {
            final fallbackDate = messageDate ?? DateTime.now();
            extracted["reference"] =
                "${pattern.bankId}_${fallbackDate.toIso8601String()}";
          }

          final requiresReference = pattern.refRequired == true;
          final requiresAccount =
              pattern.hasAccount == true && match.groupNames.contains('account');

          if (extracted['amount'] == null) {
            print(
                "✗ Pattern '${pattern.description}' matched but amount missing. Skipping.");
            continue;
          }
          if (match.groupNames.contains('balance') &&
              extracted['currentBalance'] == null) {
            print(
                "✗ Pattern '${pattern.description}' matched but balance missing. Skipping.");
            continue;
          }
          if (requiresReference && extracted['reference'] == null) {
            print(
                "✗ Pattern '${pattern.description}' matched but reference missing. Skipping.");
            continue;
          }
          if (requiresAccount && extracted['accountNumber'] == null) {
            print(
                "✗ Pattern '${pattern.description}' matched but account missing. Skipping.");
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

  static String? _normalizeType(String? rawType) {
    if (rawType == null) return null;
    final lower = rawType.toLowerCase();
    if (lower.contains('debit')) return 'DEBIT';
    if (lower.contains('credit')) return 'CREDIT';
    return null;
  }
}
