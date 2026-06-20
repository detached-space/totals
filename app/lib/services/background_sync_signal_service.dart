import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

/// Cross-isolate nudge for the Data Sync outbox. A background isolate (e.g. the
/// SMS handler) that enqueues rows calls [notifyOutboxChanged]; if a main
/// isolate is alive it receives the signal and drains. If no main isolate is
/// listening the signal is simply dropped — the rows persist and are drained by
/// the periodic WorkManager task or the next foreground launch. Mirrors
/// [BackgroundRefreshSignalService].
class BackgroundSyncSignalService {
  BackgroundSyncSignalService._();

  static final BackgroundSyncSignalService instance =
      BackgroundSyncSignalService._();

  static const String _portName = 'totals.data_sync_outbox';

  final StreamController<void> _controller =
      StreamController<void>.broadcast();

  ReceivePort? _receivePort;
  bool _isListening = false;

  Stream<void> get stream => _controller.stream;

  void ensureListening() {
    if (_isListening) return;

    final receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(receivePort.sendPort, _portName);

    receivePort.listen((_) {
      if (_controller.isClosed) return;
      _controller.add(null);
    });

    _receivePort = receivePort;
    _isListening = true;
  }

  static void notifyOutboxChanged() {
    final sendPort = IsolateNameServer.lookupPortByName(_portName);
    sendPort?.send(true);
  }

  void dispose() {
    _receivePort?.close();
    _receivePort = null;
    _isListening = false;
    IsolateNameServer.removePortNameMapping(_portName);
  }
}
