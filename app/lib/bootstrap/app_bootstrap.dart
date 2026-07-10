import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite/sqflite.dart';
import 'package:totals/_redesign/theme/theme.dart';
import 'package:totals/_redesign/widgets/finance_lock_surface.dart';
import 'package:totals/background/daily_spending_worker.dart';
import 'package:totals/database/database_helper.dart';
import 'package:totals/repositories/profile_repository.dart';
import 'package:totals/services/data_sync/data_sync_scheduler.dart';
import 'package:totals/services/data_sync/data_sync_settings_service.dart';
import 'package:totals/services/notification_scheduler.dart';
import 'package:totals/services/widget_launch_intent_service.dart';
import 'package:totals/services/widget_refresh_scheduler.dart';
import 'package:totals/services/widget_service.dart';
import 'package:totals/theme/app_theme_mode_preference.dart';
import 'package:workmanager/workmanager.dart';

enum BootstrapPhase {
  preparing,
  loadingEnvironment,
  openingDatabase,
  initializingProfile,
  initializingServices,
  schedulingBackgroundWork,
  ready,
}

extension BootstrapPhaseLabel on BootstrapPhase {
  String get label {
    switch (this) {
      case BootstrapPhase.preparing:
        return 'Preparing your finances...';
      case BootstrapPhase.loadingEnvironment:
        return 'Loading your settings...';
      case BootstrapPhase.openingDatabase:
        return 'Updating your finances...';
      case BootstrapPhase.initializingProfile:
        return 'Preparing your profile...';
      case BootstrapPhase.initializingServices:
        return 'Starting Totals...';
      case BootstrapPhase.schedulingBackgroundWork:
        return 'Finishing up...';
      case BootstrapPhase.ready:
        return 'Ready';
    }
  }

  String get diagnosticCode {
    switch (this) {
      case BootstrapPhase.preparing:
        return 'PREPARE';
      case BootstrapPhase.loadingEnvironment:
        return 'ENVIRONMENT';
      case BootstrapPhase.openingDatabase:
        return 'DATABASE';
      case BootstrapPhase.initializingProfile:
        return 'PROFILE';
      case BootstrapPhase.initializingServices:
        return 'SERVICES';
      case BootstrapPhase.schedulingBackgroundWork:
        return 'SCHEDULERS';
      case BootstrapPhase.ready:
        return 'READY';
    }
  }
}

typedef BootstrapInitializer = Future<void> Function({
  required ValueChanged<BootstrapPhase> onPhaseChanged,
});

typedef BootstrapThemeModeLoader = Future<ThemeMode> Function();

class BootstrapFailure implements Exception {
  BootstrapFailure({
    required this.phase,
    required this.error,
    required this.stackTrace,
  })  : occurredAt = DateTime.now().toUtc(),
        reference = DateTime.now()
            .toUtc()
            .microsecondsSinceEpoch
            .toRadixString(36)
            .toUpperCase();

  final BootstrapPhase phase;
  final Object error;
  final StackTrace stackTrace;
  final DateTime occurredAt;
  final String reference;

  String get safeSummary {
    switch (_category) {
      case 'storage-full':
        return 'There may not be enough free storage to finish updating the '
            'local database.';
      case 'database-locked':
        return 'The local database is temporarily busy. Closing other Totals '
            'tasks and retrying may help.';
      case 'schema-mismatch':
        return 'The local database structure could not be updated safely.';
      case 'database-corrupt':
        return 'The local database could not be read reliably.';
      case 'read-only':
        return 'Totals could not write the database update to local storage.';
      case 'plugin-unavailable':
        return 'A required device storage service was unavailable.';
      default:
        return 'Totals could not finish preparing the local database.';
    }
  }

  String get diagnosticDetails {
    final stack = _safeStackTrace(stackTrace);
    final sqliteResultCode = _sqliteResultCode;
    final migrationStage = _migrationStage;
    return <String>[
      'Totals startup diagnostic',
      'Reference: $reference',
      'Time (UTC): ${occurredAt.toIso8601String()}',
      'Phase: ${phase.diagnosticCode}',
      if (migrationStage != null) 'Migration stage: $migrationStage',
      'Category: $_category',
      'Error type: ${_sourceError.runtimeType}',
      if (sqliteResultCode != null) 'SQLite code: $sqliteResultCode',
      'Platform: ${defaultTargetPlatform.name}',
      'Mode: ${kReleaseMode ? 'release' : 'debug'}',
      if (stack.isNotEmpty) ...[
        '',
        'Stack:',
        stack,
      ],
    ].join('\n');
  }

  String get _category {
    final source = _sourceError;
    if (source is DatabaseException) {
      switch (_sqlitePrimaryCode(source.getResultCode())) {
        case 1: // SQLITE_ERROR, commonly a missing schema object.
        case 17: // SQLITE_SCHEMA.
        case 19: // SQLITE_CONSTRAINT.
          return 'schema-mismatch';
        case 5: // SQLITE_BUSY.
        case 6: // SQLITE_LOCKED.
          return 'database-locked';
        case 8: // SQLITE_READONLY.
          return 'read-only';
        case 11: // SQLITE_CORRUPT.
        case 26: // SQLITE_NOTADB.
          return 'database-corrupt';
        case 13: // SQLITE_FULL.
          return 'storage-full';
      }
      if (source.isNoSuchTableError() ||
          source.isDuplicateColumnError() ||
          source.isUniqueConstraintError() ||
          source.isSyntaxError()) {
        return 'schema-mismatch';
      }
      if (source.isReadOnlyError()) return 'read-only';
    }
    if (source is MissingPluginException) {
      return 'plugin-unavailable';
    }
    if (source is PlatformException) {
      final code = source.code.toLowerCase();
      if (code.contains('read_only') || code.contains('readonly')) {
        return 'read-only';
      }
      if (code.contains('unavailable') || code.contains('not_implemented')) {
        return 'plugin-unavailable';
      }
    }
    return 'unknown';
  }

  int? get _sqliteResultCode {
    final source = _sourceError;
    return source is DatabaseException ? source.getResultCode() : null;
  }

  Object get _sourceError {
    final source = error;
    return source is DatabaseMigrationException ? source.cause : source;
  }

  String? get _migrationStage {
    final source = error;
    return source is DatabaseMigrationException ? source.stage : null;
  }
}

int? _sqlitePrimaryCode(int? resultCode) {
  if (resultCode == null) return null;
  return resultCode & 0xFF;
}

String _safeStackTrace(StackTrace stackTrace) {
  return stackTrace
      .toString()
      .split('\n')
      .map(_safeStackFrame)
      .whereType<String>()
      .take(12)
      .join('\n');
}

String? _safeStackFrame(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed == '<asynchronous suspension>') return trimmed;

  // Preserve method names and package/Dart source locations, but remove local
  // device or developer filesystem paths from copied diagnostics.
  final locationStart = trimmed.lastIndexOf(' (');
  if (locationStart > 0 && trimmed.endsWith(')')) {
    final method = trimmed.substring(0, locationStart);
    final location = trimmed.substring(locationStart + 2, trimmed.length - 1);
    if (location.startsWith('package:') || location.startsWith('dart:')) {
      return '$method ($location)';
    }
    return method;
  }

  if (trimmed.contains('file:') || trimmed.contains(r':\')) {
    return trimmed.split(RegExp(r'\s+(?:file:|[A-Za-z]:\\)')).first;
  }
  return trimmed.length <= 240 ? trimmed : trimmed.substring(0, 240);
}

void reportNonFatalBootstrapError(
  String phase,
  Object error,
  StackTrace stackTrace,
) {
  debugPrint(
    'startup_nonfatal phase=$phase error_type=${error.runtimeType}',
  );
  final stack = _safeStackTrace(stackTrace);
  if (stack.isNotEmpty) {
    debugPrint(stack);
  }
}

class AppBootstrapper {
  AppBootstrapper._();

  static Future<void> initialize({
    required ValueChanged<BootstrapPhase> onPhaseChanged,
  }) async {
    await _runNonFatal(
      phase: BootstrapPhase.loadingEnvironment,
      onPhaseChanged: onPhaseChanged,
      task: () => dotenv.load(fileName: '.env', isOptional: true),
    );

    await _runCritical(
      phase: BootstrapPhase.openingDatabase,
      onPhaseChanged: onPhaseChanged,
      task: () async {
        await DatabaseHelper.instance.database;
      },
    );

    await _runCritical(
      phase: BootstrapPhase.initializingProfile,
      onPhaseChanged: onPhaseChanged,
      task: () => ProfileRepository().initializeDefaultProfile(),
    );

    await _runNonFatal(
      phase: BootstrapPhase.initializingServices,
      onPhaseChanged: onPhaseChanged,
      task: WidgetService.initialize,
    );
    await _runNonFatal(
      phase: BootstrapPhase.initializingServices,
      onPhaseChanged: onPhaseChanged,
      task: WidgetLaunchIntentService.instance.initialize,
    );
    await _runNonFatal(
      phase: BootstrapPhase.initializingServices,
      onPhaseChanged: onPhaseChanged,
      task: DataSyncSettingsService.instance.ensureLoaded,
    );

    if (_supportsBackgroundScheduling) {
      final workmanagerReady = await _runNonFatal(
        phase: BootstrapPhase.schedulingBackgroundWork,
        onPhaseChanged: onPhaseChanged,
        task: () => Workmanager().initialize(callbackDispatcher),
      );

      if (workmanagerReady) {
        await _runNonFatal(
          phase: BootstrapPhase.schedulingBackgroundWork,
          onPhaseChanged: onPhaseChanged,
          task: NotificationScheduler.syncSpendingSummarySchedule,
        );
        await _runNonFatal(
          phase: BootstrapPhase.schedulingBackgroundWork,
          onPhaseChanged: onPhaseChanged,
          task: NotificationScheduler.syncSharedExpenseNotificationSchedule,
        );
        await _runNonFatal(
          phase: BootstrapPhase.schedulingBackgroundWork,
          onPhaseChanged: onPhaseChanged,
          task: WidgetRefreshScheduler.syncWidgetRefreshSchedule,
        );
        await _runNonFatal(
          phase: BootstrapPhase.schedulingBackgroundWork,
          onPhaseChanged: onPhaseChanged,
          task: DataSyncScheduler.sync,
        );
      }
    }

    onPhaseChanged(BootstrapPhase.ready);
  }

  static bool get _supportsBackgroundScheduling {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static Future<void> _runCritical({
    required BootstrapPhase phase,
    required ValueChanged<BootstrapPhase> onPhaseChanged,
    required Future<void> Function() task,
  }) async {
    onPhaseChanged(phase);
    try {
      await task();
    } catch (error, stackTrace) {
      throw BootstrapFailure(
        phase: phase,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<bool> _runNonFatal({
    required BootstrapPhase phase,
    required ValueChanged<BootstrapPhase> onPhaseChanged,
    required Future<void> Function() task,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    onPhaseChanged(phase);
    try {
      await task().timeout(timeout);
      return true;
    } catch (error, stackTrace) {
      reportNonFatalBootstrapError(
        phase.diagnosticCode,
        error,
        stackTrace,
      );
      return false;
    }
  }
}

class AppBootstrapGate extends StatefulWidget {
  const AppBootstrapGate({
    super.key,
    required this.appBuilder,
    this.bootstrapInitializer,
    this.themeModeLoader,
  });

  final WidgetBuilder appBuilder;
  final BootstrapInitializer? bootstrapInitializer;
  final BootstrapThemeModeLoader? themeModeLoader;

  @override
  State<AppBootstrapGate> createState() => _AppBootstrapGateState();
}

class _AppBootstrapGateState extends State<AppBootstrapGate> {
  BootstrapPhase _phase = BootstrapPhase.preparing;
  BootstrapFailure? _failure;
  ThemeMode _themeMode = ThemeMode.system;
  bool _isRunning = false;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadThemeMode());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  Future<void> _loadThemeMode() async {
    try {
      final loader = widget.themeModeLoader ?? AppThemeModePreference.load;
      final themeMode = await loader();
      if (!mounted || themeMode == _themeMode) return;
      setState(() => _themeMode = themeMode);
    } catch (error, stackTrace) {
      reportNonFatalBootstrapError(
        'THEME_MODE',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _initialize() async {
    if (!mounted || _isRunning) return;
    setState(() {
      _isRunning = true;
      _isReady = false;
      _failure = null;
      _phase = BootstrapPhase.preparing;
    });

    try {
      final initialize =
          widget.bootstrapInitializer ?? AppBootstrapper.initialize;
      await initialize(
        onPhaseChanged: (phase) {
          if (!mounted) return;
          setState(() => _phase = phase);
        },
      );
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _isReady = true;
        _failure = null;
      });
    } on BootstrapFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _failure = failure;
        _phase = failure.phase;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _isRunning = false;
        _failure = BootstrapFailure(
          phase: _phase,
          error: error,
          stackTrace: stackTrace,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isReady) {
      return widget.appBuilder(context);
    }

    return _BootstrapMaterialApp(
      phase: _phase,
      failure: _failure,
      themeMode: _themeMode,
      onRetry: _initialize,
    );
  }
}

class _BootstrapMaterialApp extends StatelessWidget {
  const _BootstrapMaterialApp({
    required this.phase,
    required this.failure,
    required this.themeMode,
    required this.onRetry,
  });

  final BootstrapPhase phase;
  final BootstrapFailure? failure;
  final ThemeMode themeMode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: RedesignTheme.light(),
      darkTheme: RedesignTheme.dark(),
      themeMode: themeMode,
      builder: (context, child) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: theme.scaffoldBackgroundColor,
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: theme.scaffoldBackgroundColor,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: failure == null
          ? FinanceLockSurface(
              statusText: phase.label,
              showProgressIndicator: true,
            )
          : _BootstrapRecoveryPage(
              failure: failure!,
              onRetry: onRetry,
            ),
    );
  }
}

class _BootstrapRecoveryPage extends StatelessWidget {
  const _BootstrapRecoveryPage({
    required this.failure,
    required this.onRetry,
  });

  final BootstrapFailure failure;
  final VoidCallback onRetry;

  Future<void> _copyDiagnostics(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: failure.diagnosticDetails),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic details copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.storage_rounded,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "Totals couldn't open your local data",
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    failure.safeSummary,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Totals will not reset or delete your database '
                    'automatically. You can retry safely or copy the '
                    'details below for support.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _copyDiagnostics(context),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy diagnostic details'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Diagnostic details',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SelectableText(
                      failure.diagnosticDetails,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
