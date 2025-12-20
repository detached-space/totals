import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/services/account_sync_status_service.dart';
import 'package:totals/screens/home_page.dart';
import 'package:totals/database/migration_helper.dart';
import 'package:workmanager/workmanager.dart';
import 'package:totals/background/daily_spending_worker.dart';
import 'package:totals/services/notification_scheduler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database and migrate if needed
  // await MigrationHelper.migrateIfNeeded();

  if (!kIsWeb) {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
        isInDebugMode: kDebugMode,
      );
      await NotificationScheduler.syncDailySummarySchedule();
    } catch (e) {
      // Ignore if not supported on the current platform.
      if (kDebugMode) {
        print('debug: Workmanager init failed: $e');
      }
    }
  }

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider.value(value: AccountSyncStatusService.instance),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Totals',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.blue,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.dark(
                primary: const Color(0xFF294EC3),
                secondary: const Color(0xFF3B5FE8),
                surface: const Color(0xFF0A0E1A),
                background: const Color(0xFF0A0E1A),
                surfaceVariant: const Color(0xFF1A1F2E),
                onPrimary: Colors.white,
                onSecondary: Colors.white,
                onSurface: Colors.white,
                onBackground: Colors.white,
                onSurfaceVariant: Colors.white70,
                brightness: Brightness.dark,
              ),
              scaffoldBackgroundColor: const Color(0xFF0A0E1A),
              cardColor: const Color(0xFF1A1F2E),
              dividerColor: const Color(0xFF2A2F3E),
              useMaterial3: true,
            ),
            themeMode: themeProvider.themeMode,
            home: const HomePage(),
          );
        },
      ),
    );
  }
}
