import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:totals/models/shared_expense_group.dart';

class SharedExpenseRealtimeBus {
  SharedExpenseRealtimeBus._();

  static final SharedExpenseRealtimeBus instance =
      SharedExpenseRealtimeBus._();

  final StreamController<SharedExpenseGroup> _controller =
      StreamController<SharedExpenseGroup>.broadcast();

  Stream<SharedExpenseGroup> get stream => _controller.stream;

  void publish(SharedExpenseGroup group) {
    if (_controller.isClosed) return;
    if (kDebugMode) {
      final hash = identityHashCode(this);
      debugPrint(
        'debug: SharedExpenseRealtimeBus publish bus=$hash group=${group.id} '
        'hasListener=${_controller.hasListener} '
        'pendingApprovals=${group.pendingApprovals.length} '
        'activity=${group.activity.length}',
      );
    }
    _controller.add(group);
  }
}
