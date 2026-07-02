import 'package:totals/models/bank.dart';
import 'package:totals/models/sms_pattern.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/transaction_link_utils.dart';

class PatternParser {
  /// Iterates through [patterns] that match the [senderAddress].
  /// Returns a map of extracted data if a match is found, or null otherwise.
  static Future<Map<String, dynamic>?> extractTransactionDetails(
      String messageBody,
      String senderAddress,
      DateTime? messageDate,
      List<SmsPattern> patterns,
      {List<Bank>? banks}) async {
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
          // We support: amount, balance, account, reference, creditor, receiver,
          // sender/source (for incoming transfers), time

          extracted['type'] = pattern.type;
          extracted['bankId'] = pattern.bankId; // Default bank ID from pattern
          extracted['patternDescription'] = pattern.description;

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
              final availableBanks =
                  banks ?? await BankConfigService().getBanks();
              final bank =
                  availableBanks.firstWhere((b) => b.id == pattern.bankId);

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
          _assignOptionalAmount(
            extracted,
            'serviceCharge',
            match,
            const [
              'serviceCharge',
              'ServiceCharge',
              'servicecharge',
              'service_charge'
            ],
          );
          _assignOptionalAmount(
            extracted,
            'vat',
            match,
            const ['vat', 'VAT'],
          );
          String? counterparty = _firstNamedGroup(match, const [
            'sender',
            'source',
            'agent',
            'payer',
            'from',
          ]);
          final rawType = (extracted['type'] ?? pattern.type).toString();
          final normalized = rawType.toUpperCase();
          if (normalized.contains('CREDIT')) {
            counterparty ??= _fallbackCounterparty(cleanBody);
            if (counterparty != null && counterparty.trim().isNotEmpty) {
              extracted['creditor'] ??= counterparty.trim();
            }
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

          final transactionLink =
              TransactionLinkUtils.extractTransactionLinkFromMessage(
            messageBody: cleanBody,
            pattern: pattern,
            reference: extracted['reference']?.toString(),
          );
          if (transactionLink != null) {
            extracted['transactionLink'] = transactionLink;
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
          final requiresAccount = pattern.hasAccount == true &&
              match.groupNames.contains('account');

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

  static void _assignOptionalAmount(
    Map<String, dynamic> target,
    String key,
    RegExpMatch match,
    List<String> groupNames,
  ) {
    for (final name in groupNames) {
      if (!match.groupNames.contains(name)) continue;
      final cleaned = _cleanNumber(match.namedGroup(name));
      final value = cleaned == null ? null : double.tryParse(cleaned);
      if (value != null) {
        target[key] = value;
      }
      return;
    }
  }

  static String? _firstNamedGroup(
    RegExpMatch match,
    List<String> groupNames,
  ) {
    for (final name in groupNames) {
      if (!match.groupNames.contains(name)) continue;
      final value = match.namedGroup(name);
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static String? _fallbackCounterparty(String body) {
    final patterns = [
      RegExp(
        r'from\s+(.+?)\s+(?:to|on|at|ref|reference|transaction|balance)',
        caseSensitive: false,
      ),
      RegExp(
        r'by\s+(.+?)\s+(?:on|through|ref|reference|transaction|balance)',
        caseSensitive: false,
      ),
      RegExp(
        r'with\s+agent\s+(.+?)\s+(?:on|at|ref|reference|transaction|balance)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(body);
      if (match == null) continue;
      final value = match.group(1)?.trim();
      if (value == null || value.isEmpty) continue;
      if (value.toLowerCase().contains('your account')) continue;
      if (value.toLowerCase().contains('your telebirr')) continue;
      if (value.toLowerCase().contains('your mpesa')) continue;
      return value;
    }
    return null;
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
