import 'package:flutter/foundation.dart';

import '../services/financial_insights.dart';
import 'transaction_provider.dart';

class InsightsProvider extends ChangeNotifier {
  TransactionProvider _txProvider;
  late final InsightsService _service;

  InsightsProvider({required TransactionProvider txProvider})
      : _txProvider = txProvider {
    // we will use live transactions from existing provider,

    _service = InsightsService(
      () => _txProvider.transactions,
      getCategoryById: _txProvider.getCategoryById,
    );
    _txProvider.addListener(_onTxChange);
  }

  Map<String, dynamic> get insights => _service.summarize();

  // allow ProxyProvider to update when TransactionProvider is updated.
  set txProvider(TransactionProvider newProvider) {
    if (identical(_txProvider, newProvider)) return;

    _txProvider.removeListener(_onTxChange);
    _txProvider = newProvider;
    // Recreate service with new provider's getCategoryById
    _service = InsightsService(
      () => _txProvider.transactions,
      getCategoryById: _txProvider.getCategoryById,
    );
    _txProvider.addListener(_onTxChange);
    _service.invalidate(); // clear the cache
    notifyListeners();
  }

  @override
  void dispose() {
    _txProvider.removeListener(_onTxChange);
    super.dispose();
  }

  void _onTxChange() {
    // Invalidate cache when tx data updates, then nofify listeners.
    _service.invalidate();
    notifyListeners();
  }
}
