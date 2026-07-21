import 'package:meta/meta.dart';
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

          final mapping = pattern.fieldMapping;
          final Map<String, dynamic> extracted = {};

          extracted['type'] = pattern.type;
          extracted['bankId'] = pattern.bankId;
          extracted['patternDescription'] = pattern.description;

          String? typeOverride;
          if (_hasGroup(match, mapping, 'type')) {
            typeOverride = _normalizeType(_groupValue(match, mapping, 'type'));
          }
          final transactionType = typeOverride ?? pattern.type;

          double? amount = _hasGroup(match, mapping, 'amount')
              ? double.tryParse(
                  _cleanNumber(_groupValue(match, mapping, 'amount')) ?? "")
              : null;
          if (amount != null) {
            extracted['amount'] = amount;
          }

          String? currentBalance = _hasGroup(match, mapping, 'balance')
              ? _cleanNumber(_groupValue(match, mapping, 'balance'))
              : null;
          if (currentBalance != null) {
            extracted['currentBalance'] = currentBalance;
          }

          String? reference = _hasGroup(match, mapping, 'reference')
              ? _groupValue(match, mapping, 'reference')
              : null;

          String? accountNumber;
          if (_hasGroup(match, mapping, 'account')) {
            print("debug: ✓ after account - entering account extraction block");
            String? raw = _groupValue(match, mapping, 'account');
            print("debug: Raw account value: '$raw'");

            if (raw != null) {
              final availableBanks =
                  banks ?? await BankConfigService().getBanks();
              final bank =
                  availableBanks.firstWhere((b) => b.id == pattern.bankId);

              if (bank.uniformMasking == true && bank.maskPattern != null) {
                if (raw.length >= bank.maskPattern!) {
                  accountNumber =
                      raw.substring(raw.length - bank.maskPattern!);
                  print("Cleaned account (masked): $accountNumber");
                } else {
                  accountNumber = raw;
                  print("Cleaned account (fallback): $accountNumber");
                }
              } else {
                accountNumber = raw;
                print("Cleaned account (direct): $accountNumber");
              }
            } else {
              print("debug: ✗ Raw account is null!");
            }
            if (accountNumber != null) {
              extracted['accountNumber'] = accountNumber;
            }
          } else {
            print("debug: ✗ 'account' group NOT found in named groups");
          }

          if (reference == null) {
            if (pattern.refRequired == false) {
              final fallbackDate = messageDate ?? DateTime.now();
              final typePart = transactionType;
              final amountPart = amount?.toStringAsFixed(2) ?? 'NA';
              final accountPart = accountNumber ?? 'NA';
              reference =
                  "${pattern.bankId}_${typePart}_${amountPart}_${accountPart}_${fallbackDate.toIso8601String()}";
            }
          }
          if (reference != null) {
            extracted['reference'] = reference;
          }

          String? creditor;
          String? receiver;
          if (_hasGroup(match, mapping, 'creditor')) {
            creditor = _groupValue(match, mapping, 'creditor');
          }
          if (_hasGroup(match, mapping, 'receiver')) {
            receiver = _groupValue(match, mapping, 'receiver');
          }
          if (creditor != null) extracted['creditor'] = creditor;
          if (receiver != null) extracted['receiver'] = receiver;

          double? serviceCharge = _extractOptionalAmount(match, mapping, const [
            'serviceCharge', 'ServiceCharge', 'servicecharge', 'service_charge'
          ]);
          double? vat = _extractOptionalAmount(match, mapping, const ['vat', 'VAT']);
          double? totalDebit = _extractOptionalAmount(
              match, mapping, const ['totalAmount']);
          double? totalFee = _extractOptionalAmount(
              match, mapping, const ['totalFees', 'total_amount']);

          if (serviceCharge != null) extracted['serviceCharge'] = serviceCharge;
          if (vat != null) extracted['vat'] = vat;
          if (totalDebit != null) extracted['totalDebit'] = totalDebit;
          if (totalFee != null) extracted['totalFee'] = totalFee;

          String? counterparty = _firstNamedGroup(match, mapping, const [
            'sender', 'source', 'agent', 'payer', 'from',
          ]);
          final rawType = transactionType;
          final normalizedType = rawType.toUpperCase();
          if (normalizedType.contains('CREDIT')) {
            counterparty ??= _fallbackCounterparty(cleanBody);
            if (counterparty != null && counterparty.trim().isNotEmpty) {
              extracted['creditor'] ??= counterparty.trim();
            }
          }

          String? time;
          if (_hasGroup(match, mapping, 'time')) {
            time = _groupValue(match, mapping, 'time');
          }
          if (time != null && messageDate != null) {
            time = composeDateTime(messageDate!, time);
          }
          time ??= messageDate?.toIso8601String();
          extracted['time'] = time;

          final transactionLink =
              TransactionLinkUtils.extractTransactionLinkFromMessage(
            messageBody: cleanBody,
            pattern: pattern,
            reference: reference,
          );
          if (transactionLink != null) {
            extracted['transactionLink'] = transactionLink;
          }

          print("debug: account $accountNumber");
          print("debug: amount $amount");
          print("debug: balance $currentBalance");
          print("debug: reference $reference");
          print("debug: receiver $receiver");

          final requiresReference = pattern.refRequired == true;
          final requiresAccount = pattern.hasAccount == true &&
              _hasGroup(match, mapping, 'account');

          if (amount == null &&
              serviceCharge != null &&
              vat != null &&
              totalDebit != null) {
            amount = totalDebit - serviceCharge - vat;
            if (amount != null && amount >= 0) {
              extracted['amount'] = amount;
            }
          }
          if (!extracted.containsKey('totalFee') &&
              serviceCharge != null &&
              vat != null) {
            extracted['totalFee'] = serviceCharge + vat;
          }

          if (extracted['amount'] == null) {
            print(
                "✗ Pattern '${pattern.description}' matched but amount missing. Skipping.");
            continue;
          }
          if (_hasGroup(match, mapping, 'balance') &&
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

  static String? _groupValue(RegExpMatch match, Map<String, String>? mapping, String name) {
    if (mapping != null && mapping.containsKey(name)) {
      final index = int.tryParse(mapping[name]!);
      if (index != null) return match.group(index);
    }
    return match.namedGroup(name);
  }

  static bool _hasGroup(RegExpMatch match, Map<String, String>? mapping, String name) {
    if (mapping != null && mapping.containsKey(name)) {
      final index = int.tryParse(mapping[name]!);
      if (index != null) return index < match.groupCount + 1;
    }
    return match.groupNames.contains(name);
  }

  static double? _extractOptionalAmount(
      RegExpMatch match,
      Map<String, String>? mapping,
      List<String> groupNames) {
    for (final name in groupNames) {
      if (!_hasGroup(match, mapping, name)) continue;
      final cleaned = _cleanNumber(_groupValue(match, mapping, name));
      final value = cleaned == null ? null : double.tryParse(cleaned);
      if (value != null) return value;
    }
    return null;
  }

  static void _assignOptionalAmount(
    Map<String, dynamic> target,
    String key,
    RegExpMatch match,
    List<String> groupNames,
  ) {
    final value = _extractOptionalAmount(match, null, groupNames);
    if (value != null) {
      target[key] = value;
    }
  }

  static String? _firstNamedGroup(
    RegExpMatch match,
    Map<String, String>? mapping,
    List<String> groupNames,
  ) {
    for (final name in groupNames) {
      if (!_hasGroup(match, mapping, name)) continue;
      final value = _groupValue(match, mapping, name);
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

  @visibleForTesting
  static String? composeDateTime(DateTime messageDate, String timeFragment) {
    final trimmed = timeFragment.trim();
    if (trimmed.isEmpty) return null;

    final match12h = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)$', caseSensitive: false).firstMatch(trimmed);
    if (match12h != null) {
      var hour = int.parse(match12h.group(1)!);
      final minute = int.parse(match12h.group(2)!);
      final second = match12h.group(3) != null ? int.parse(match12h.group(3)!) : 0;
      if (hour < 1 || hour > 12 || minute > 59 || second > 59) return null;
      final isPm = match12h.group(4)!.toUpperCase() == 'PM';
      if (isPm && hour != 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;
      return DateTime(
        messageDate.year, messageDate.month, messageDate.day,
        hour, minute, second,
      ).toIso8601String();
    }

    final match24h = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(trimmed);
    if (match24h != null) {
      final hour = int.parse(match24h.group(1)!);
      final minute = int.parse(match24h.group(2)!);
      final second = match24h.group(3) != null ? int.parse(match24h.group(3)!) : 0;
      if (hour > 23 || minute > 59 || second > 59) return null;
      return DateTime(
        messageDate.year, messageDate.month, messageDate.day,
        hour, minute, second,
      ).toIso8601String();
    }

    return null;
  }
}
