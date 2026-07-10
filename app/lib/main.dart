import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:totals/bootstrap/app_bootstrap.dart';
import 'package:totals/providers/insights_provider.dart';
import 'package:totals/providers/theme_provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/providers/budget_provider.dart';
import 'package:totals/screens/home_page.dart';
import 'package:totals/services/account_sync_status_service.dart';
import 'package:totals/services/shared_expense_push_notification_service.dart';
import 'package:totals/services/data_sync/sync_enqueuer.dart';
import 'package:totals/_redesign/screens/onboarding_page.dart';
import 'package:totals/_redesign/screens/redesign_shell.dart';
import 'package:totals/_redesign/theme/theme.dart';
import 'package:totals/theme/app_font_option.dart';

SnackBarThemeData _globalSnackBarTheme() {
  return SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: const Color(0xFF334155),
    contentTextStyle: const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    ),
    insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    elevation: 0,
  );
}

Widget _buildAppTopPadding({
  required BuildContext context,
  required Widget child,
  required Color backgroundColor,
  required double topPadding,
}) {
  final mediaQuery = MediaQuery.of(context);

  return ColoredBox(
    color: backgroundColor,
    child: MediaQuery(
      data: mediaQuery.copyWith(
        padding: mediaQuery.padding.copyWith(
          top: mediaQuery.padding.top + topPadding,
        ),
        viewPadding: mediaQuery.viewPadding.copyWith(
          top: mediaQuery.viewPadding.top + topPadding,
        ),
      ),
      child: child,
    ),
  );
}

Widget _buildUiScaledApp({
  required BuildContext context,
  required Widget child,
  required double scale,
}) {
  if ((scale - 1.0).abs() < 0.001) return child;

  // Use sizeOf instead of MediaQuery.of to only depend on size changes,
  // not every MediaQuery field (avoids unnecessary rebuilds during theme changes
  // that can crash overlay elements like bottom sheets).
  final size = MediaQuery.sizeOf(context);
  final scaledWidth = size.width / scale;
  final scaledHeight = size.height / scale;

  return ClipRect(
    child: OverflowBox(
      alignment: Alignment.topLeft,
      minWidth: scaledWidth,
      maxWidth: scaledWidth,
      minHeight: scaledHeight,
      maxHeight: scaledHeight,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: scaledWidth,
          height: scaledHeight,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Flag this as the main isolate so the Data Sync enqueuer drains inline here
  // (background isolates defer to the periodic task / signal bridge instead).
  SyncEnqueuer.isMainIsolate = true;
  try {
    SharedExpensePushNotificationService.registerBackgroundHandler();
  } catch (error, stackTrace) {
    reportNonFatalBootstrapError(
      'PUSH_REGISTRATION',
      error,
      stackTrace,
    );
  }

  runApp(
    AppBootstrapGate(
      appBuilder: (_) => const MyApp(
        useRedesign: true,
        showOnboarding: false,
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  final bool useRedesign;
  final bool showOnboarding;

  const MyApp({
    super.key,
    required this.useRedesign,
    this.showOnboarding = false,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => TransactionProvider()),
        ChangeNotifierProvider(create: (_) => BudgetProvider()),

        // we need insights provider to use the existing transacton provider instead of using
        // a new transaction provider instance.
        ChangeNotifierProxyProvider<TransactionProvider, InsightsProvider>(
          create: (context) => InsightsProvider(
              txProvider:
                  Provider.of<TransactionProvider>(context, listen: false)),
          update: (context, txProvider, previous) =>
              previous!..txProvider = txProvider,
        ),
        ChangeNotifierProvider.value(value: AccountSyncStatusService.instance),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Totals',
            theme: useRedesign
                ? RedesignTheme.light(fontOption: themeProvider.appFont)
                : AppFontTheme.applyLegacy(
                    ThemeData(
                      colorScheme: ColorScheme.fromSeed(
                        seedColor: Colors.blue,
                        brightness: Brightness.light,
                      ),
                      snackBarTheme: _globalSnackBarTheme(),
                      useMaterial3: true,
                    ),
                    themeProvider.appFont,
                  ),
            darkTheme: useRedesign
                ? RedesignTheme.dark(fontOption: themeProvider.appFont)
                : AppFontTheme.applyLegacy(
                    ThemeData(
                      colorScheme: const ColorScheme.dark(
                        primary: Color(0xFF3F3F46),
                        secondary: Color(0xFF52525B),
                        surface: Color(0xFF1E2230),
                        background: Color(0xFF161A26),
                        surfaceVariant: Color(0xFF161A26),
                        onPrimary: Colors.white,
                        onSecondary: Colors.white,
                        onSurface: Colors.white,
                        onBackground: Colors.white,
                        onSurfaceVariant: Colors.white70,
                        brightness: Brightness.dark,
                      ),
                      scaffoldBackgroundColor: const Color(0xFF161A26),
                      cardColor: const Color(0xFF1E2230),
                      dividerColor: const Color(0xFF34384A),
                      snackBarTheme: _globalSnackBarTheme(),
                      useMaterial3: true,
                    ),
                    themeProvider.appFont,
                  ),
            themeMode: themeProvider.themeMode,
            builder: (context, child) {
              if (child == null) return const SizedBox.shrink();
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;
              final overlayStyle = SystemUiOverlayStyle(
                statusBarColor: theme.scaffoldBackgroundColor,
                statusBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
                statusBarBrightness:
                    isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: theme.scaffoldBackgroundColor,
                systemNavigationBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
              );
              return _buildUiScaledApp(
                context: context,
                scale: themeProvider.uiScale,
                child: AnnotatedRegion<SystemUiOverlayStyle>(
                  value: overlayStyle,
                  child: _buildAppTopPadding(
                    context: context,
                    backgroundColor: theme.scaffoldBackgroundColor,
                    topPadding: themeProvider.appTopPadding,
                    child: child,
                  ),
                ),
              );
            },
            home: showOnboarding
                ? const OnboardingPage()
                : useRedesign
                    ? const RedesignShell()
                    : const HomePage(),
          );
        },
      ),
    );
  }
}
