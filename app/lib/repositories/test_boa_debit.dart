void main() {
  final debitSms = '''
Dear EYOSIAS, your account 1***54 was debited with ETB 4,011.50.
Available Balance:  ETB 527.39.
Receipt: https://cs.bankofabyssinia.com/slip/?trx=FT251810567N97854
Feedback: https://cs.bankofabyssinia.com/cs/?trx=DFT251810567N
''';

  // Normalize whitespace to handle newlines and extra spaces
  final normalizedSms = debitSms.replaceAll(RegExp(r'\s+'), ' ').trim();

  final debitRegex = RegExp(
    r'account\s+(?<account>[\d\*]+)\s+was\s+debited\s+with\s+ETB\s+(?<amount>[\d,.]+)\s*\.\s*Available\s+Balance:\s*ETB\s+(?<balance>[\d,.]+)\s*\.\s*Receipt:\s*https?:\/\/\S+\?trx=(?<reference>FT[A-Z0-9]+)',
    caseSensitive: false,
    dotAll: true,
  );

  final match = debitRegex.firstMatch(normalizedSms);

  if (match != null) {
    print('✅ BOA Debit Match');
    print('account   : ${match.namedGroup('account')}');
    print('amount    : ${match.namedGroup('amount')}');
    print('balance   : ${match.namedGroup('balance')}');
    print('reference : ${match.namedGroup('reference')}');
  } else {
    print('❌ No match found for BOA Debit');
  }
}
