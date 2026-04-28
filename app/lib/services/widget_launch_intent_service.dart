import 'dart:async';

import 'package:flutter/services.dart';

enum WidgetLaunchTarget {
  budget,
}

class WidgetLaunchIntentService {
  WidgetLaunchIntentService._();

  static final WidgetLaunchIntentService instance =
      WidgetLaunchIntentService._();

  static const MethodChannel _channel =
      MethodChannel('detached.totals/widget_launch');

  final StreamController<WidgetLaunchTarget> _controller =
      StreamController<WidgetLaunchTarget>.broadcast();

  WidgetLaunchTarget? _pendingTarget;

  Stream<WidgetLaunchTarget> get stream => _controller.stream;

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'launchTarget') return;
      _handleIncomingTarget(call.arguments);
    });

    try {
      final initialTarget = await _channel.invokeMethod<String>(
        'consumeLaunchTarget',
      );
      _handleIncomingTarget(initialTarget, emit: false);
    } on MissingPluginException {
      // Ignore on platforms that do not expose the launch channel.
    } on PlatformException {
      // Ignore if the host side does not yet expose the channel.
    }
  }

  WidgetLaunchTarget? consumePendingTarget() {
    final target = _pendingTarget;
    _pendingTarget = null;
    return target;
  }

  void _handleIncomingTarget(
    dynamic rawTarget, {
    bool emit = true,
  }) {
    final target = _parseTarget(rawTarget);
    if (target == null) return;

    _pendingTarget = target;
    if (!_controller.isClosed && emit) {
      _controller.add(target);
    }
  }

  WidgetLaunchTarget? _parseTarget(dynamic rawTarget) {
    final target = rawTarget?.toString().trim().toLowerCase();
    if (target == 'budget') {
      return WidgetLaunchTarget.budget;
    }
    return null;
  }

  void dispose() {
    _controller.close();
  }
}
