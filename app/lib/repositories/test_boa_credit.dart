void main() {
  final creditSms = '''
Dear EYOSIAS, your account 1***54 was credited with ETB 15,471.14 by CASHGO SUSPENSE ACCOUNT (RECEIVABLE.
Available Balance:  ETB 15,562.64.
Receipt: https://cs.bankofabyssinia.com/slip/?trx=FT25181B4XJS10001
Feedback: https://cs.bankofabyssinia.com/cs/?trx=CFT25181B4XJS
''';

  // Normalize whitespace to handle newlines and extra spaces
  final normalizedSms = creditSms.replaceAll(RegExp(r'\s+'), ' ').trim();

  final creditRegex = RegExp(
    r'account\s+(?<account>[\d\*]+).*?credited\s+with\s+ETB\s+(?<amount>[\d,.]+)\s+by\s+(?<source>[\s\S]+?)\s+Available\s+Balance:\s+ETB\s+(?<balance>[\d,.]+).*?Receipt:\s*https?:\/\/\S+\?trx=(?<reference>FT[A-Z0-9]+)',
    caseSensitive: false,
    dotAll: true,
  );

  final match = creditRegex.firstMatch(normalizedSms);

  if (match != null) {
    print('✅ BOA Credit Match');
    print('account   : ${match.namedGroup('account')}');
    print('amount    : ${match.namedGroup('amount')}');
    print('balance   : ${match.namedGroup('balance')}');
    print('reference : ${match.namedGroup('reference')}');
    print('source    : ${match.namedGroup('source')}');
  } else {
    print('❌ No match found for BOA Credit');
  }
}
