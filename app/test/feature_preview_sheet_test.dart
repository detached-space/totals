import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/widgets/feature_preview_sheet.dart';
import 'package:totals/providers/theme_provider.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(
      envString:
          '$tutorialsBucketUrlEnvironmentKey=https://tutorials.example.invalid/',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('default previews use versioned R2 videos and cache keys', () {
    expect(totalsFeaturePreviews, hasLength(2));
    final autoCategorizationPreview = totalsFeaturePreviews.first;
    final quickAccessAccountPreview = totalsFeaturePreviews.last;

    expect(autoCategorizationPreview.videoUrl, autoCategorizationPreviewUrl);
    expect(
      autoCategorizationPreview.videoUrl,
      'https://tutorials.example.invalid/'
      'tutorials/v1/auto-categorization.mp4',
    );
    expect(
      autoCategorizationPreview.videoCacheKey,
      autoCategorizationPreviewCacheKey,
    );
    expect(
      Uri.parse(autoCategorizationPreview.videoUrl).path,
      '/tutorials/v1/auto-categorization.mp4',
    );
    expect(
      autoCategorizationPreview.videoPlaceholderAsset,
      autoCategorizationPreviewPlaceholderAsset,
    );

    expect(quickAccessAccountPreview.title, 'Quick Account Access');
    expect(quickAccessAccountPreview.videoUrl, quickAccessAccountPreviewUrl);
    expect(
      quickAccessAccountPreview.videoCacheKey,
      quickAccessAccountPreviewCacheKey,
    );
    expect(
      Uri.parse(quickAccessAccountPreview.videoUrl).path,
      '/tutorials/v1/quick-access-account.mp4',
    );
    expect(
      quickAccessAccountPreview.videoPlaceholderAsset,
      quickAccessAccountPreviewPlaceholderAsset,
    );
  });

  test('blurred first-frame placeholders are bundled as app assets', () async {
    for (final preview in totalsFeaturePreviews) {
      final placeholder = await rootBundle.load(
        preview.videoPlaceholderAsset,
      );

      expect(placeholder.lengthInBytes, greaterThan(0));
    }
  });

  testWidgets('close and Okay dismiss the feature preview sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(initialThemeMode: ThemeMode.system),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showTestFeaturePreviewSheet(context),
                  child: const Text('Open preview'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open preview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Auto-Categorization'), findsOneWidget);
    expect(
      find.text(autoCategorizationPreviewDescription),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.text(autoCategorizationPreviewDescription))
          .textAlign,
      TextAlign.justify,
    );
    expect(find.byKey(const Key('feature-preview-close')), findsOneWidget);
    expect(
      find.byKey(const Key('feature-preview-placeholder')),
      findsOneWidget,
    );
    expect(find.text('Okay'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text(autoCategorizationPreviewDescription)).dy,
      lessThan(
        tester.getTopLeft(find.widgetWithText(FilledButton, 'Okay')).dy,
      ),
    );

    await tester.tap(find.byKey(const Key('feature-preview-close')));
    await tester.pumpAndSettle();

    expect(find.text('Okay'), findsNothing);

    await tester.tap(find.text('Open preview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(FilledButton, 'Okay'));
    await tester.pumpAndSettle();

    expect(find.text('Okay'), findsNothing);
  });

  testWidgets('multiple previews use a swipeable pager and horizontal nav', (
    tester,
  ) async {
    const previews = <FeaturePreviewItem>[
      FeaturePreviewItem(
        title: 'First tutorial',
        summary: 'First summary',
        description: 'First description',
        videoUrl: 'https://example.com/tutorials/v1/first.mp4',
        videoCacheKey: 'tutorials/v1/first.mp4',
        videoPlaceholderAsset: autoCategorizationPreviewPlaceholderAsset,
        icon: Icons.looks_one_rounded,
        accentColor: Colors.indigo,
      ),
      FeaturePreviewItem(
        title: 'Second tutorial',
        summary: 'Second summary',
        description: 'Second description',
        videoUrl: 'https://example.com/tutorials/v1/second.mp4',
        videoCacheKey: 'tutorials/v1/second.mp4',
        videoPlaceholderAsset: autoCategorizationPreviewPlaceholderAsset,
        icon: Icons.looks_two_rounded,
        accentColor: Colors.pink,
      ),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(initialThemeMode: ThemeMode.system),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showFeaturePreviewSheet(
                  context,
                  items: previews,
                ),
                child: const Text('Open previews'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open previews'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final navigation = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('feature-preview-navigation')),
    );
    expect(navigation.scrollDirection, Axis.horizontal);
    expect(
      find.descendant(
        of: find.byKey(const Key('feature-preview-navigation')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('feature-preview-indicator-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('feature-preview-indicator-1')),
      findsOneWidget,
    );
    for (var index = 0; index < previews.length; index++) {
      final dotFinder = find.byKey(
        ValueKey<String>('feature-preview-dot-$index'),
      );
      final dot = tester.widget<SizedBox>(dotFinder);
      expect(dot.width, 7);
      expect(dot.height, 7);

      final decoration = tester
          .widget<DecoratedBox>(
            find.descendant(
              of: dotFinder,
              matching: find.byType(DecoratedBox),
            ),
          )
          .decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
    }

    PageView pages = tester.widget<PageView>(
      find.byKey(const Key('feature-preview-pages')),
    );
    expect(pages.controller!.page, 0);

    await tester.drag(
      find.byKey(const Key('feature-preview-pages')),
      const Offset(-700, 0),
    );
    // Video loading deliberately keeps an indeterminate progress indicator
    // active, so only advance through the page transition here.
    await tester.pump(const Duration(milliseconds: 500));

    pages = tester.widget<PageView>(
      find.byKey(const Key('feature-preview-pages')),
    );
    expect(pages.controller!.page, 1);
  });

  testWidgets(
    'rapid swipes reuse one player and serialize video source changes',
    (tester) async {
      late _ControllableBetterPlayerController playerController;
      var factoryCalls = 0;

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(initialThemeMode: ThemeMode.system),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => showFeaturePreviewSheet(
                    context,
                    playerControllerFactory: (configuration) {
                      factoryCalls++;
                      playerController = _ControllableBetterPlayerController(
                        configuration,
                      );
                      return playerController;
                    },
                  ),
                  child: const Text('Open shared player preview'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open shared player preview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(factoryCalls, 1);
      expect(playerController.dataSources, hasLength(1));
      expect(
        playerController.dataSources.single.url,
        autoCategorizationPreviewUrl,
      );
      expect(playerController.maximumConcurrentSetups, 1);

      for (final offset in const <Offset>[
        Offset(-700, 0),
        Offset(700, 0),
        Offset(-700, 0),
      ]) {
        await tester.drag(
          find.byKey(const Key('feature-preview-pages')),
          offset,
        );
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.tap(
        find.byKey(
          const ValueKey<String>('feature-preview-indicator-1'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(factoryCalls, 1);
      expect(playerController.dataSources, hasLength(1));
      expect(playerController.concurrentSetups, 1);

      playerController.completeNextSetup();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(playerController.dataSources, hasLength(2));
      expect(
        playerController.dataSources.last.url,
        quickAccessAccountPreviewUrl,
      );
      expect(playerController.maximumConcurrentSetups, 1);
      expect(playerController.concurrentSetups, 1);

      await tester.tap(find.byKey(const Key('feature-preview-close')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(playerController.disposeCalls, 1);
      expect(playerController.wasForceDisposed, isTrue);

      playerController.completeNextSetup();
      await tester.pump();
    },
  );
}

class _ControllableBetterPlayerController extends BetterPlayerController {
  _ControllableBetterPlayerController(
    BetterPlayerConfiguration configuration,
  ) : super(configuration);

  final List<BetterPlayerDataSource> dataSources = <BetterPlayerDataSource>[];
  final List<Completer<void>> _pendingSetups = <Completer<void>>[];
  int concurrentSetups = 0;
  int maximumConcurrentSetups = 0;
  int disposeCalls = 0;
  bool wasForceDisposed = false;

  @override
  Future<void> setupDataSource(BetterPlayerDataSource dataSource) {
    dataSources.add(dataSource);
    concurrentSetups++;
    if (concurrentSetups > maximumConcurrentSetups) {
      maximumConcurrentSetups = concurrentSetups;
    }

    final completer = Completer<void>();
    _pendingSetups.add(completer);
    return completer.future.whenComplete(() => concurrentSetups--);
  }

  void completeNextSetup() {
    _pendingSetups.removeAt(0).complete();
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> setLooping(bool looping) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  bool? isBuffering() => false;

  @override
  void dispose({bool forceDispose = false}) {
    disposeCalls++;
    wasForceDisposed = forceDispose;
  }
}
