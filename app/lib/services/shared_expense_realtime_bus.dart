import 'dart:async';

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
    _controller.add(group);
  }
}
