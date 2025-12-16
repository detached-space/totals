
import 'package:flutter/foundation.dart';

import '../services/financial_insights.dart';
import 'transaction_provider.dart';

class InsightsProvider extends ChangeNotifier {
  final TransactionProvider txProvider;
  late final InsightsService _service;

  InsightsProvider({required this.txProvider}) {
    // we will use live transactions from existing provider,

    _service = InsightsService(() => txProvider.transactions);
    txProvider.addListener(_onTxChange);
  }

  void _onTxChange() {
    // Invalidate cache when tx data updates, then nofify listeners.
    _service.invalidate();
    notifyListeners();
  }

  Map<String, dynamic> get insights => _service.summarize();

  @override
  void dispose() {
    txProvider.removeListener(_onTxChange);
    super.dispose();
  }
}
