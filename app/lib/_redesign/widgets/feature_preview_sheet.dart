import 'dart:async';
import 'dart:math' as math;

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/l10n/app_localizations.dart';

const String tutorialsBucketUrlEnvironmentKey = 'TUTORIALS_BUCKET_URL';
const String autoCategorizationPreviewPlaceholderAsset =
    'assets/images/tutorials/auto_categorization_blurred.webp';
const String autoCategorizationPreviewCacheKey =
    'tutorials/v1/auto-categorization.mp4';
const double featurePreviewAspectRatio = 876 / 810;
const String autoCategorizationPreviewDescription =
    'Tap any transaction to open its details, then choose a category. Totals will remember and auto-categorize future transactions to the same recipient.';
const String quickAccessAccountPreviewPlaceholderAsset =
    'assets/images/tutorials/quick_access_account_blurred.webp';
const String quickAccessAccountPreviewCacheKey =
    'tutorials/v1/quick-access-account.mp4';
const String quickAccessAccountPreviewDescription =
    'Long-press Shared in the bottom navigation to open Account Hub. Search your saved accounts or switch to Mine, then tap an account to copy its number.';
const String reimbursementPreviewPlaceholderAsset =
    'assets/images/tutorials/reimbursement_blurred.webp';
const String reimbursementPreviewCacheKey = 'tutorials/v1/reimbursement.mp4';
const String reimbursementPreviewDescription =
    'Open an incoming transaction and link it to the original expense as a reimbursement. Totals adjusts your spending and budgets by the amount you received.';
const String telegramBackupPreviewPlaceholderAsset =
    'assets/images/tutorials/telegram_backup_blurred.webp';
const String telegramBackupPreviewCacheKey = 'tutorials/v1/telegram-backup.mp4';
const String telegramBackupPreviewDescription =
    'Connect your own private Telegram bot for encrypted backups. Totals encrypts everything on your device, supports automatic weekly backups, and restores with your recovery key.';
const int _featurePreviewCacheSize = 100 * 1024 * 1024;
const int _featurePreviewCacheFileSize = 20 * 1024 * 1024;

String get autoCategorizationPreviewUrl =>
    _tutorialVideoUrl(autoCategorizationPreviewCacheKey);

String get quickAccessAccountPreviewUrl =>
    _tutorialVideoUrl(quickAccessAccountPreviewCacheKey);

String get reimbursementPreviewUrl =>
    _tutorialVideoUrl(reimbursementPreviewCacheKey);

String get telegramBackupPreviewUrl =>
    _tutorialVideoUrl(telegramBackupPreviewCacheKey);

String _tutorialVideoUrl(String objectKey) {
  if (!dotenv.isInitialized) {
    throw StateError(
      'Tutorial videos are not configured. Load .env before opening '
      'Discover Totals.',
    );
  }

  final configuredUrl =
      dotenv.maybeGet(tutorialsBucketUrlEnvironmentKey)?.trim();
  if (configuredUrl == null || configuredUrl.isEmpty) {
    throw StateError(
      '$tutorialsBucketUrlEnvironmentKey is missing from .env.',
    );
  }

  final normalizedUrl = configuredUrl.replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(normalizedUrl);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw StateError(
      '$tutorialsBucketUrlEnvironmentKey must be a valid HTTPS URL.',
    );
  }

  return '$normalizedUrl/$objectKey';
}

typedef FeaturePreviewPlayerControllerFactory = BetterPlayerController Function(
  BetterPlayerConfiguration configuration,
);

const BetterPlayerConfiguration _featurePreviewPlayerConfiguration =
    BetterPlayerConfiguration(
  aspectRatio: featurePreviewAspectRatio,
  autoPlay: false,
  looping: true,
  fit: BoxFit.fill,
  autoDispose: false,
  expandToFill: true,
  controlsConfiguration: BetterPlayerControlsConfiguration(
    showControls: false,
  ),
);

BetterPlayerController _createFeaturePreviewPlayerController(
  BetterPlayerConfiguration configuration,
) {
  return BetterPlayerController(configuration);
}

@immutable
class FeaturePreviewItem {
  const FeaturePreviewItem({
    required this.title,
    required this.summary,
    required this.description,
    required this.videoUrl,
    required this.videoCacheKey,
    required this.videoPlaceholderAsset,
    required this.icon,
    required this.accentColor,
    this.isNew = false,
  });

  final String title;
  final String summary;
  final String description;
  final String videoUrl;
  final String videoCacheKey;
  final String videoPlaceholderAsset;
  final IconData icon;
  final Color accentColor;
  final bool isNew;
}

List<FeaturePreviewItem> get totalsFeaturePreviews =>
    List<FeaturePreviewItem>.unmodifiable(
      <FeaturePreviewItem>[
        FeaturePreviewItem(
          title: 'Auto-Categorization',
          summary: 'Future transactions matched automatically',
          description: autoCategorizationPreviewDescription,
          videoUrl: autoCategorizationPreviewUrl,
          videoCacheKey: autoCategorizationPreviewCacheKey,
          videoPlaceholderAsset: autoCategorizationPreviewPlaceholderAsset,
          icon: Icons.auto_awesome_rounded,
          accentColor: AppColors.primaryLight,
        ),
        FeaturePreviewItem(
          title: 'Quick Account Access',
          summary: 'Long-press Shared to find and copy accounts',
          description: quickAccessAccountPreviewDescription,
          videoUrl: quickAccessAccountPreviewUrl,
          videoCacheKey: quickAccessAccountPreviewCacheKey,
          videoPlaceholderAsset: quickAccessAccountPreviewPlaceholderAsset,
          icon: Icons.account_balance_wallet_rounded,
          accentColor: AppColors.blue,
        ),
        FeaturePreviewItem(
          title: 'Link Reimbursements',
          summary: 'Track returned money against past spending',
          description: reimbursementPreviewDescription,
          videoUrl: reimbursementPreviewUrl,
          videoCacheKey: reimbursementPreviewCacheKey,
          videoPlaceholderAsset: reimbursementPreviewPlaceholderAsset,
          icon: Icons.currency_exchange_rounded,
          accentColor: AppColors.blue,
          isNew: true,
        ),
        FeaturePreviewItem(
          title: 'Telegram Backup',
          summary: 'Encrypted backups in your private bot chat',
          description: telegramBackupPreviewDescription,
          videoUrl: telegramBackupPreviewUrl,
          videoCacheKey: telegramBackupPreviewCacheKey,
          videoPlaceholderAsset: telegramBackupPreviewPlaceholderAsset,
          icon: Icons.send_rounded,
          accentColor: AppColors.primaryLight,
          isNew: true,
        ),
      ],
    );

Future<void> showFeaturePreviewSheet(
  BuildContext context, {
  List<FeaturePreviewItem>? items,
  int initialIndex = 0,
  FeaturePreviewPlayerControllerFactory playerControllerFactory =
      _createFeaturePreviewPlayerController,
}) {
  final configuredItems = items ?? totalsFeaturePreviews;
  if (configuredItems.isEmpty) {
    throw ArgumentError.value(
      configuredItems,
      'items',
      'Must contain at least one item',
    );
  }

  final previews = List<FeaturePreviewItem>.unmodifiable(configuredItems);
  final resolvedInitialIndex = initialIndex < 0
      ? 0
      : initialIndex >= previews.length
          ? previews.length - 1
          : initialIndex;

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.black.withValues(alpha: 0.68),
    builder: (_) => _FeaturePreviewSheet(
      items: previews,
      initialIndex: resolvedInitialIndex,
      playerControllerFactory: playerControllerFactory,
    ),
  );
}

Future<void> showTestFeaturePreviewSheet(BuildContext context) {
  return showFeaturePreviewSheet(context);
}

class _FeaturePreviewSheet extends StatefulWidget {
  const _FeaturePreviewSheet({
    required this.items,
    required this.initialIndex,
    required this.playerControllerFactory,
  });

  final List<FeaturePreviewItem> items;
  final int initialIndex;
  final FeaturePreviewPlayerControllerFactory playerControllerFactory;

  @override
  State<_FeaturePreviewSheet> createState() => _FeaturePreviewSheetState();
}

class _FeaturePreviewSheetState extends State<_FeaturePreviewSheet> {
  late final PageController _pageController;
  late final List<GlobalKey> _navigationKeys;
  late final BetterPlayerController _videoController;
  late final void Function(BetterPlayerEvent) _videoEventListener;
  late int _selectedIndex;
  late int _requestedVideoIndex;
  int? _readyVideoIndex;
  int? _loadingVideoIndex;
  int? _errorVideoIndex;
  Object? _initializationError;
  bool _isBuffering = false;
  bool _isSwitchingVideo = false;
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _requestedVideoIndex = _selectedIndex;
    _loadingVideoIndex = _selectedIndex;
    _pageController = PageController(initialPage: _selectedIndex);
    _navigationKeys = List<GlobalKey>.generate(
      widget.items.length,
      (_) => GlobalKey(),
    );
    _videoController = widget.playerControllerFactory(
      _featurePreviewPlayerConfiguration,
    );
    _videoEventListener = _handleVideoEvent;
    _videoController.addEventsListener(_videoEventListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureNavigationItemVisible(_selectedIndex, animate: false);
      unawaited(_processVideoRequests());
    });
  }

  @override
  void dispose() {
    _isDisposing = true;
    _pageController.dispose();
    _videoController.removeEventsListener(_videoEventListener);
    _videoController.dispose(forceDispose: true);
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _selectedIndex = index);
    _requestVideo(index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureNavigationItemVisible(index);
    });
  }

  void _requestVideo(int index, {bool force = false}) {
    if (!mounted || _isDisposing) return;

    final requestAlreadyPending = !force &&
        _requestedVideoIndex == index &&
        _initializationError == null &&
        (_readyVideoIndex == index || _loadingVideoIndex == index);
    if (requestAlreadyPending) return;

    setState(() {
      _requestedVideoIndex = index;
      _readyVideoIndex = null;
      _loadingVideoIndex = index;
      _errorVideoIndex = null;
      _initializationError = null;
      _isBuffering = false;
    });
    unawaited(_pauseVideo());
    unawaited(_processVideoRequests());
  }

  bool get _requestedVideoIsSettled =>
      _readyVideoIndex == _requestedVideoIndex ||
      _errorVideoIndex == _requestedVideoIndex;

  Future<void> _processVideoRequests() async {
    if (_isSwitchingVideo || _isDisposing) return;
    _isSwitchingVideo = true;

    try {
      while (mounted && !_isDisposing && !_requestedVideoIsSettled) {
        final index = _requestedVideoIndex;
        await _loadVideo(index);
      }
    } finally {
      _isSwitchingVideo = false;
      if (mounted && !_isDisposing && !_requestedVideoIsSettled) {
        unawaited(_processVideoRequests());
      }
    }
  }

  Future<void> _loadVideo(int index) async {
    if (!mounted || _isDisposing || _requestedVideoIndex != index) return;

    if (_loadingVideoIndex != index || _initializationError != null) {
      setState(() {
        _readyVideoIndex = null;
        _loadingVideoIndex = index;
        _errorVideoIndex = null;
        _initializationError = null;
        _isBuffering = false;
      });
    }

    try {
      await _pauseVideo();
      if (!mounted || _isDisposing || _requestedVideoIndex != index) return;

      final item = widget.items[index];
      await _videoController.setupDataSource(
        BetterPlayerDataSource.network(
          item.videoUrl,
          videoFormat: BetterPlayerVideoFormat.other,
          cacheConfiguration: BetterPlayerCacheConfiguration(
            useCache: true,
            maxCacheSize: _featurePreviewCacheSize,
            maxCacheFileSize: _featurePreviewCacheFileSize,
            key: item.videoCacheKey,
          ),
        ),
      );

      if (!mounted || _isDisposing || _requestedVideoIndex != index) {
        await _pauseVideo();
        return;
      }

      await _videoController.setLooping(true);
      await _videoController.setVolume(0);
      if (!mounted ||
          _isDisposing ||
          _requestedVideoIndex != index ||
          _errorVideoIndex == index) {
        await _pauseVideo();
        return;
      }

      await _videoController.play();
      if (!mounted || _isDisposing || _requestedVideoIndex != index) {
        await _pauseVideo();
        return;
      }

      setState(() {
        _readyVideoIndex = index;
        _loadingVideoIndex = null;
        _errorVideoIndex = null;
        _initializationError = null;
        _isBuffering = _videoController.isBuffering() ?? false;
      });
    } catch (error) {
      if (!mounted || _isDisposing || _requestedVideoIndex != index) return;
      setState(() {
        _readyVideoIndex = null;
        _loadingVideoIndex = null;
        _errorVideoIndex = index;
        _initializationError = error;
        _isBuffering = false;
      });
    }
  }

  Future<void> _pauseVideo() async {
    try {
      await _videoController.pause();
    } catch (_) {
      // A source can be changing or the sheet can be closing.
    }
  }

  void _handleVideoEvent(BetterPlayerEvent event) {
    final readyIndex = _readyVideoIndex;
    if (!mounted ||
        _isDisposing ||
        readyIndex == null ||
        readyIndex != _selectedIndex) {
      return;
    }

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.exception:
        final error = StateError(
          event.parameters?['exception']?.toString() ??
              "Couldn't load feature preview",
        );
        setState(() {
          _readyVideoIndex = null;
          _loadingVideoIndex = null;
          _errorVideoIndex = readyIndex;
          _initializationError = error;
          _isBuffering = false;
        });
        unawaited(_pauseVideo());
        break;
      case BetterPlayerEventType.bufferingStart:
        if (!_isBuffering) setState(() => _isBuffering = true);
        break;
      case BetterPlayerEventType.bufferingEnd:
        if (_isBuffering) setState(() => _isBuffering = false);
        break;
      default:
        break;
    }
  }

  void _ensureNavigationItemVisible(int index, {bool animate = true}) {
    if (!mounted || widget.items.length < 2) return;
    final navigationContext = _navigationKeys[index].currentContext;
    if (navigationContext == null) return;
    Scrollable.ensureVisible(
      navigationContext,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 240) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  void _selectPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final hasNavigation = widget.items.length > 1;
    final desiredHeight =
        size.width / featurePreviewAspectRatio + 280 + (hasNavigation ? 32 : 0);
    final sheetHeight = math.min(size.height * 0.96, desiredHeight);

    return Material(
      color: AppColors.cardColor(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: sheetHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  Expanded(
                    child: PageView.builder(
                      key: const Key('feature-preview-pages'),
                      controller: _pageController,
                      itemCount: widget.items.length,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (context, index) {
                        final item = widget.items[index];
                        final isActive = index == _selectedIndex;
                        final isReady = isActive && _readyVideoIndex == index;
                        return _FeaturePreviewPage(
                          key: ValueKey<String>('${item.videoUrl}:$index'),
                          item: item,
                          isActive: isActive,
                          videoController: isReady ? _videoController : null,
                          isBuffering: isReady && _isBuffering,
                          initializationError:
                              isActive && _errorVideoIndex == index
                                  ? _initializationError
                                  : null,
                          onRetry: () => _requestVideo(index, force: true),
                        );
                      },
                    ),
                  ),
                  if (hasNavigation)
                    _FeaturePreviewNavigation(
                      items: widget.items,
                      itemKeys: _navigationKeys,
                      pageController: _pageController,
                      selectedIndex: _selectedIndex,
                      onSelected: _selectPage,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: AppColors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Okay',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  key: const Key('feature-preview-close'),
                  tooltip: context.l10nText('Close'),
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.black.withValues(alpha: 0.5),
                    foregroundColor: AppColors.white,
                    minimumSize: const Size(40, 40),
                    maximumSize: const Size(40, 40),
                    padding: const EdgeInsets.all(8),
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturePreviewPage extends StatelessWidget {
  const _FeaturePreviewPage({
    super.key,
    required this.item,
    required this.isActive,
    required this.videoController,
    required this.isBuffering,
    required this.initializationError,
    required this.onRetry,
  });

  final FeaturePreviewItem item;
  final bool isActive;
  final BetterPlayerController? videoController;
  final bool isBuffering;
  final Object? initializationError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxVideoHeight = MediaQuery.sizeOf(context).height * 0.52;

    return Column(
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxVideoHeight),
            child: _buildVideo(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
          child: Column(
            children: [
              Text(
                context.l10nText(item.title),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10nText(item.description),
                textAlign: TextAlign.justify,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary(context),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVideo(BuildContext context) {
    final Widget content;

    if (!isActive) {
      content = _buildPlaceholder(
        context: context,
        key: ValueKey<String>(
          'feature-preview-idle-${item.videoCacheKey}',
        ),
        showLoadingIndicator: false,
      );
    } else if (initializationError != null) {
      content = _buildPlaceholder(
        context: context,
        key: const ValueKey<String>('feature-preview-error-state'),
        hasError: true,
      );
    } else if (videoController == null) {
      content = _buildPlaceholder(
        context: context,
        key: const ValueKey<String>('feature-preview-loading-state'),
      );
    } else {
      content = _buildStreamingVideo();
    }

    return AspectRatio(
      aspectRatio: featurePreviewAspectRatio,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) => Stack(
            fit: StackFit.expand,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _buildPlaceholder({
    required BuildContext context,
    required Key key,
    bool hasError = false,
    bool showLoadingIndicator = true,
  }) {
    return Stack(
      key: key,
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: 1.03,
          child: Image.asset(
            item.videoPlaceholderAsset,
            key: const Key('feature-preview-placeholder'),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
          ),
        ),
        ColoredBox(
          color: AppColors.black.withValues(alpha: hasError ? 0.46 : 0.1),
        ),
        Center(
          child: hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.videocam_off_outlined,
                      color: AppColors.white,
                      size: 36,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.l10nText("Couldn't load preview"),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      key: const Key('feature-preview-retry'),
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.white,
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                      label: Text(context.l10nText('Retry')),
                    ),
                  ],
                )
              : showLoadingIndicator
                  ? _buildLoadingIndicator()
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildStreamingVideo() {
    final controller = videoController!;

    return Semantics(
      key: const ValueKey<String>('feature-preview-streaming-video'),
      label: '${item.title} feature preview video',
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: 1.03,
            child: BetterPlayer(
              key: const Key('feature-preview-shared-player'),
              controller: controller,
            ),
          ),
          if (isBuffering) Center(child: _buildLoadingIndicator()),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.42),
        shape: BoxShape.circle,
      ),
      child: const Padding(
        padding: EdgeInsets.all(10),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            color: AppColors.white,
            strokeWidth: 2.5,
          ),
        ),
      ),
    );
  }
}

class _FeaturePreviewNavigation extends StatelessWidget {
  const _FeaturePreviewNavigation({
    required this.items,
    required this.itemKeys,
    required this.pageController,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<FeaturePreviewItem> items;
  final List<GlobalKey> itemKeys;
  final PageController pageController;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  double _selectionProgress(double page, int index) {
    return (1 - (page - index).abs()).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const Key('feature-preview-navigation'),
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: AnimatedBuilder(
              animation: pageController,
              builder: (context, child) {
                final page = pageController.hasClients
                    ? pageController.page ?? selectedIndex.toDouble()
                    : selectedIndex.toDouble();
                final inactiveColor =
                    AppColors.textTertiary(context).withValues(alpha: 0.38);

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var index = 0; index < items.length; index++)
                      Semantics(
                        key: itemKeys[index],
                        label:
                            'Page ${index + 1} of ${items.length}: ${context.l10nText(items[index].title)}',
                        selected: index == selectedIndex,
                        button: true,
                        child: InkWell(
                          key: ValueKey<String>(
                            'feature-preview-indicator-$index',
                          ),
                          onTap: () => onSelected(index),
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: Center(
                              child: SizedBox.square(
                                key: ValueKey<String>(
                                  'feature-preview-dot-$index',
                                ),
                                dimension: 7,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color.lerp(
                                      inactiveColor,
                                      items[index].accentColor,
                                      Curves.easeOutCubic.transform(
                                        _selectionProgress(page, index),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
