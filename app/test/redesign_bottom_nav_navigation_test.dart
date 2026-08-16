import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/widgets/redesign_bottom_nav.dart';
import 'package:totals/providers/theme_provider.dart';

void main() {
  testWidgets(
    'jumps directly to a distant page while the nav indicator animates',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final harnessKey = GlobalKey<_DirectNavigationHarnessState>();

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            home: _DirectNavigationHarness(key: harnessKey),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final indicator = find.byKey(
        const ValueKey('bottom-nav-selection-indicator'),
      );
      final initialIndicatorX = tester.getCenter(indicator).dx;

      await tester.tap(find.text('You'));
      await tester.pump();

      expect(harnessKey.currentState!.page, 4);
      expect(tester.getCenter(indicator).dx, initialIndicatorX);

      await tester.pump(const Duration(milliseconds: 125));
      final movingIndicatorX = tester.getCenter(indicator).dx;
      expect(movingIndicatorX, greaterThan(initialIndicatorX));

      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getCenter(indicator).dx, greaterThan(movingIndicatorX));
      expect(harnessKey.currentState!.page, 4);
    },
  );

  testWidgets(
    'moves the nav indicator continuously with a page swipe',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final harnessKey = GlobalKey<_DirectNavigationHarnessState>();

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            home: _DirectNavigationHarness(key: harnessKey),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final indicator = find.byKey(
        const ValueKey('bottom-nav-selection-indicator'),
      );
      final initialIndicatorX = tester.getCenter(indicator).dx;
      final moneyIndicatorX = tester.getCenter(find.text('Money')).dx;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Page 0')),
      );

      await gesture.moveBy(const Offset(-240, 0));
      await tester.pump();

      final draggedIndicatorX = tester.getCenter(indicator).dx;
      expect(draggedIndicatorX, greaterThan(initialIndicatorX));
      expect(draggedIndicatorX, lessThan(moneyIndicatorX));

      await gesture.moveBy(const Offset(-240, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(harnessKey.currentState!.page, 1);
      expect(
        tester.getCenter(indicator).dx,
        closeTo(moneyIndicatorX, 0.01),
      );
    },
  );
}

class _DirectNavigationHarness extends StatefulWidget {
  const _DirectNavigationHarness({super.key});

  @override
  State<_DirectNavigationHarness> createState() =>
      _DirectNavigationHarnessState();
}

class _DirectNavigationHarnessState extends State<_DirectNavigationHarness> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  double? get page => _pageController.page;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _selectPage(int index) {
    setState(() => _currentIndex = index);
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        children: List<Widget>.generate(
          5,
          (index) => Center(child: Text('Page $index')),
        ),
      ),
      bottomNavigationBar: RedesignBottomNav(
        currentIndex: _currentIndex,
        pageController: _pageController,
        onTap: _selectPage,
      ),
    );
  }
}
