import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/_redesign/screens/redesign_shell.dart';
import 'package:totals/l10n/app_localizations.dart';

const String _kOnboardingCompleteKey = 'has_completed_onboarding';

// ─── Data classes ────────────────────────────────────────────────────────────

class _Feature {
  final IconData icon;
  final String title;
  final String description;
  const _Feature({
    required this.icon,
    required this.title,
    required this.description,
  });
}

final List<_Feature> _features = [
  _Feature(
    icon: AppIcons.sms_outlined,
    title: 'SMS Tracking',
    description: 'Auto-detect transactions from bank messages',
  ),
  _Feature(
    icon: AppIcons.account_balance,
    title: 'Multi-Bank Support',
    description: 'CBE, Awash, BOA, Dashen & Telebirr',
  ),
  _Feature(
    icon: AppIcons.auto_graph_rounded,
    title: 'Smart Analytics',
    description: 'Charts & insights on your spending',
  ),
  _Feature(
    icon: AppIcons.savings_outlined,
    title: 'Budget Goals',
    description: 'Set targets & track by category',
  ),
];

class _TourSlide {
  final String title;
  final String description;
  final int highlightedNavIndex;

  const _TourSlide({
    required this.title,
    required this.description,
    required this.highlightedNavIndex,
  });
}

const List<_TourSlide> _tourSlides = [
  _TourSlide(
    title: 'Home',
    description:
        'Your total balance, daily and weekly summaries, and recent transactions.',
    highlightedNavIndex: 0,
  ),
  _TourSlide(
    title: 'Money',
    description:
        'Search and filter transactions, view analytics charts, and browse a chronological ledger.',
    highlightedNavIndex: 1,
  ),
  _TourSlide(
    title: 'Accounts',
    description:
        'Add and manage your bank accounts. See transactions, balances, and details.',
    highlightedNavIndex: 1,
  ),
  _TourSlide(
    title: 'Budget',
    description:
        'Set monthly budgets by category, track spending, and stay on top of your goals.',
    highlightedNavIndex: 2,
  ),
];

// ─── Animation helper ────────────────────────────────────────────────────────

double _progress(double t, double begin, double end,
    [Curve curve = Curves.easeOutCubic]) {
  final raw = ((t - begin) / (end - begin)).clamp(0.0, 1.0);
  return curve.transform(raw);
}

// ─── Main OnboardingPage ─────────────────────────────────────────────────────

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const int _totalPages = 6;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding({bool openAddAccount = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingCompleteKey, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const RedesignShell(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _skip() => _completeOnboarding();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) => setState(() => _currentPage = index),
          children: [
            _WelcomeSlide(
              isActive: _currentPage == 0,
              onGetStarted: _nextPage,
              onSkip: _skip,
            ),
            for (int i = 0; i < _tourSlides.length; i++)
              _TourSlideWidget(
                isActive: _currentPage == i + 1,
                slide: _tourSlides[i],
                slideIndex: i,
                pageIndex: i + 1,
                totalPages: _totalPages,
                onNext: _nextPage,
                onPrev: _prevPage,
                onSkip: _skip,
              ),
            _AddAccountSlide(
              isActive: _currentPage == 5,
              onAddAccount: () => _completeOnboarding(openAddAccount: true),
              onSkip: _completeOnboarding,
              onBack: _prevPage,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page indicator dots ────────────────────────────────────────────────────

class _PageDots extends StatelessWidget {
  final int total;
  final int current;

  const _PageDots({required this.total, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 24 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: isActive
                ? AppColors.primaryLight
                : AppColors.textTertiary(context).withOpacity(0.3),
          ),
        );
      }),
    );
  }
}

// ─── Screen 1: Welcome ──────────────────────────────────────────────────────

class _WelcomeSlide extends StatefulWidget {
  final bool isActive;
  final VoidCallback onGetStarted;
  final VoidCallback onSkip;

  const _WelcomeSlide({
    required this.isActive,
    required this.onGetStarted,
    required this.onSkip,
  });

  @override
  State<_WelcomeSlide> createState() => _WelcomeSlideState();
}

class _WelcomeSlideState extends State<_WelcomeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.isActive) {
      Future.microtask(() {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void didUpdateWidget(_WelcomeSlide old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _fadeSlide(double t, double begin, double end, Widget child,
      {double dx = 0, double dy = 20}) {
    final p = _progress(t, begin, end);
    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(dx * (1 - p), dy * (1 - p)),
        child: child,
      ),
    );
  }

  Widget _fadeScale(double t, double begin, double end, Widget child) {
    final p = _progress(t, begin, end);
    final sp = _progress(t, begin, end, Curves.easeOutBack);
    return Opacity(
      opacity: p,
      child: Transform.scale(
        scale: 0.5 + 0.5 * sp,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              _fadeSlide(
                t,
                0.0,
                0.25,
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _PageDots(total: 6, current: 0),
                      GestureDetector(
                        onTap: widget.onSkip,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                dy: -12,
              ),
              const Spacer(flex: 2),
              _fadeScale(
                t,
                0.05,
                0.35,
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: SvgPicture.asset(
                    'assets/images/logo.svg',
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _fadeSlide(
                  t,
                  0.15,
                  0.40,
                  Text(
                    'Welcome to Totals',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  )),
              const SizedBox(height: 8),
              _fadeSlide(
                  t,
                  0.22,
                  0.47,
                  Text(
                    'Your personal finance tracker.\nSmarter spending starts here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                      color: AppColors.textSecondary(context),
                    ),
                  )),
              const SizedBox(height: 28),
              for (int i = 0; i < _features.length; i++)
                _fadeSlide(
                  t,
                  0.30 + i * 0.07,
                  0.52 + i * 0.07,
                  _FeatureRow(feature: _features[i]),
                  dx: 20,
                  dy: 4,
                ),
              const SizedBox(height: 24),
              _fadeSlide(
                  t,
                  0.68,
                  0.95,
                  GestureDetector(
                    onTap: widget.onGetStarted,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Get Started',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(AppIcons.arrow_forward,
                              size: 18, color: AppColors.white),
                        ],
                      ),
                    ),
                  )),
              const Spacer(flex: 3),
            ],
          ),
        );
      },
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final _Feature feature;
  const _FeatureRow({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(feature.icon, size: 22, color: AppColors.primaryLight),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10nText(feature.title),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary(context),
                    )),
                const SizedBox(height: 2),
                Text(context.l10nText(feature.description),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary(context),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Screens 2–5: Feature tour ──────────────────────────────────────────────

class _TourSlideWidget extends StatefulWidget {
  final bool isActive;
  final _TourSlide slide;
  final int slideIndex;
  final int pageIndex;
  final int totalPages;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onSkip;

  const _TourSlideWidget({
    required this.isActive,
    required this.slide,
    required this.slideIndex,
    required this.pageIndex,
    required this.totalPages,
    required this.onNext,
    required this.onPrev,
    required this.onSkip,
  });

  @override
  State<_TourSlideWidget> createState() => _TourSlideWidgetState();
}

class _TourSlideWidgetState extends State<_TourSlideWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    if (widget.isActive) _ctrl.forward();
  }

  @override
  void didUpdateWidget(_TourSlideWidget old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _buildPreview(BuildContext context) {
    switch (widget.slideIndex) {
      case 0:
        return const _HomePreview();
      case 1:
        return const _MoneyPreview();
      case 2:
        return const _AccountsPreview();
      case 3:
        return const _BudgetPreview();
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final previewP = _progress(t, 0.0, 0.45);
        final barP = _progress(t, 0.25, 0.70);

        return Column(
          children: [
            Opacity(
              opacity: _progress(t, 0.0, 0.3),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _PageDots(
                        total: widget.totalPages, current: widget.pageIndex),
                    GestureDetector(
                      onTap: widget.onSkip,
                      child: Text(
                        context.l10nText('Skip'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Opacity(
                opacity: previewP,
                child: Transform.scale(
                  scale: 0.92 + 0.08 * previewP,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    decoration: BoxDecoration(
                      color: AppColors.background(context),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.borderColor(context)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.black.withOpacity(0.04),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildPreview(context),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, 20 * (1 - barP)),
              child: Opacity(
                opacity: barP,
                child: _TourBottomBar(
                  title: widget.slide.title,
                  description: widget.slide.description,
                  highlightedNavIndex: widget.slide.highlightedNavIndex,
                  onNext: widget.onNext,
                  onPrev: widget.onPrev,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─── Preview: Home (matches _TotalBalanceCard + TransactionTile) ─────────────

class _HomePreview extends StatelessWidget {
  const _HomePreview();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Balance card – matches _TotalBalanceCard in home_page.dart
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL BALANCE',
                  style: TextStyle(
                    color: AppColors.white.withOpacity(0.85),
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'ETB 45.2K',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Container(height: 1, color: AppColors.white.withOpacity(0.22)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _balanceDelta('Today', '+1.2K', '-850')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _balanceDelta('This week', '+8.5K', '-3.2K')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // "Today (3)" header
          Text(
            'Today (3)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          // Transaction tiles – match TransactionTile widget exactly
          _MiniTxTile(
            bank: 'CBE',
            category: 'Groceries',
            amount: '- ETB 850',
            amountColor: AppColors.red,
            name: 'ELIAS MARKET',
          ),
          _MiniTxTile(
            bank: 'Telebirr',
            category: 'Salary',
            amount: '+ ETB 15K',
            amountColor: AppColors.incomeSuccess,
            name: 'COMPANY INC',
            categoryColor: AppColors.incomeSuccess,
          ),
          _MiniTxTile(
            bank: 'Awash',
            category: 'Categorize',
            amount: '- ETB 120',
            amountColor: AppColors.red,
            name: 'UBER',
            isCategorized: false,
          ),
        ],
      ),
    );
  }

  static Widget _balanceDelta(String label, String income, String expense) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.white.withOpacity(0.85),
            fontSize: 8,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(income,
                style: const TextStyle(
                    color: AppColors.incomeSuccess,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            Container(
                width: 1, height: 8, color: AppColors.white.withOpacity(0.35)),
            const SizedBox(width: 4),
            Text(expense,
                style: const TextStyle(
                    color: AppColors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}

// ─── Preview: Money (matches money_page.dart tabs + transactions) ───────────

class _MoneyPreview extends StatelessWidget {
  const _MoneyPreview();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top tab bar – matches _TopTabBar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              _topTab(context, 'Activity', true),
              const SizedBox(width: 16),
              _topTab(context, 'Accounts', false),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: AppColors.borderColor(context)),
        Expanded(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sub-tabs – matches Transactions | Analytics | Ledger
                Row(
                  children: [
                    _subTab(context, 'Transactions', true),
                    const SizedBox(width: 6),
                    _subTab(context, 'Analytics', false),
                    const SizedBox(width: 6),
                    _subTab(context, 'Ledger', false),
                  ],
                ),
                const SizedBox(height: 8),
                // Search bar
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceColor(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.borderColor(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          size: 14, color: AppColors.textTertiary(context)),
                      const SizedBox(width: 6),
                      Text(context.l10nText('Search...'),
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textTertiary(context))),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Date header
                Text(context.l10nText('Today, Mar 10'),
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary(context))),
                const SizedBox(height: 6),
                const _MiniTxTile(
                  bank: 'CBE',
                  category: 'Groceries',
                  amount: '- ETB 450',
                  amountColor: AppColors.red,
                  name: 'SHEGER BREAD',
                ),
                const _MiniTxTile(
                  bank: 'Telebirr',
                  category: 'Transfer',
                  amount: '+ ETB 2K',
                  amountColor: AppColors.incomeSuccess,
                  name: 'JOHN DOE',
                  categoryColor: AppColors.incomeSuccess,
                ),
                const _MiniTxTile(
                  bank: 'BOA',
                  category: 'Categorize',
                  amount: '- ETB 680',
                  amountColor: AppColors.red,
                  name: 'ETHIO ELECTRIC',
                  isCategorized: false,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Widget _topTab(BuildContext context, String label, bool active) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        color: active
            ? AppColors.textPrimary(context)
            : AppColors.textTertiary(context),
      ),
    );
  }

  static Widget _subTab(BuildContext context, String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active
            ? AppColors.primaryLight.withOpacity(0.12)
            : AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? AppColors.primaryLight.withOpacity(0.3)
              : AppColors.borderColor(context),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active
              ? AppColors.primaryLight
              : AppColors.textSecondary(context),
        ),
      ),
    );
  }
}

// ─── Preview: Accounts (gradient bank cards with golden chip) ────────────────

class _AccountsPreview extends StatelessWidget {
  const _AccountsPreview();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _accountCard(
            name: 'CBE',
            number: '1000 **** 4523',
            balance: '32,100 ETB',
            subtitle: '1 Account',
            gradientColors: const [Color(0xFF1b0b2e), Color(0xFF3a0f5c)],
          ),
          const SizedBox(height: 8),
          _accountCard(
            name: 'TELEBIRR',
            number: '0912 **** 89',
            balance: '8,430 ETB',
            subtitle: '1 Account',
            gradientColors: const [
              Color(0xFF1d38e5),
              Color(0xFF90d5ee),
            ],
          ),
          const SizedBox(height: 8),
          _accountCard(
            name: 'BOA',
            number: '2000 **** 7801',
            balance: '4,700 ETB',
            subtitle: '1 Account',
            gradientColors: const [Color(0xFFd9b90b), Color(0xFF382e0c)],
          ),
        ],
      ),
    );
  }

  static Widget _accountCard({
    required String name,
    required String number,
    required String balance,
    required String subtitle,
    required List<Color> gradientColors,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Glossy overlay
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.0),
                  ],
                  stops: const [0.0, 0.4],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(name,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0)),
                  Opacity(
                      opacity: 0.7,
                      child: Icon(Icons.account_balance,
                          color: Colors.white, size: 14)),
                ],
              ),
              const SizedBox(height: 8),
              // Golden chip + account number
              Row(
                children: [
                  // Golden chip
                  Container(
                    width: 28,
                    height: 20,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.amber.shade300,
                          Colors.amber.shade500,
                          Colors.amber.shade600,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: Colors.amber.shade700.withOpacity(0.3)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    number,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                balance,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Preview: Budget (matches BudgetCard with progress bars) ────────────────

class _BudgetPreview extends StatelessWidget {
  const _BudgetPreview();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Month selector
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceColor(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderColor(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.chevron_left,
                      size: 12, color: AppColors.textTertiary(context)),
                  const SizedBox(width: 8),
                  Text(context.l10nText('March 2026'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(context))),
                  const SizedBox(width: 8),
                  Icon(AppIcons.chevron_right,
                      size: 12, color: AppColors.textTertiary(context)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Budget card 1 – matches BudgetCard exactly
          _miniBudgetCard(
            context,
            name: 'Monthly Spending',
            status: 'ON TRACK',
            statusColor: const Color(0xFF00C853),
            spent: 'ETB 18,500.00',
            budget: 'ETB 25,000.00',
            progress: 0.74,
            pctLabel: '74.0% consumed',
            remaining: 'ETB 6,500.00 left',
            isPositive: true,
          ),
          const SizedBox(height: 8),
          _miniBudgetCard(
            context,
            name: 'Food & Dining',
            status: 'WARNING',
            statusColor: const Color(0xFFFFB300),
            spent: 'ETB 4,200.00',
            budget: 'ETB 5,000.00',
            progress: 0.84,
            pctLabel: '84.0% consumed',
            remaining: 'ETB 800.00 left',
            isPositive: true,
          ),
        ],
      ),
    );
  }

  static Widget _miniBudgetCard(
    BuildContext context, {
    required String name,
    required String status,
    required Color statusColor,
    required String spent,
    required String budget,
    required double progress,
    required String pctLabel,
    required String remaining,
    required bool isPositive,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: icon + name + status
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(AppIcons.savings_outlined,
                    size: 14, color: AppColors.primaryLight),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: AppColors.textPrimary(context))),
                    Text(status,
                        style: TextStyle(
                            fontSize: 7,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: statusColor)),
                  ],
                ),
              ),
              Icon(AppIcons.chevron_right,
                  size: 14,
                  color: AppColors.textTertiary(context).withOpacity(0.5)),
            ],
          ),
          const SizedBox(height: 12),
          // SPENT / BUDGET
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10nText('SPENT'),
                      style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: AppColors.textTertiary(context))),
                  const SizedBox(height: 3),
                  Text(spent,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: AppColors.textPrimary(context))),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(context.l10nText('BUDGET'),
                      style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: AppColors.textTertiary(context))),
                  const SizedBox(height: 3),
                  Text(budget,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary(context))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress bar – matches BudgetProgressBar
          Container(
            height: 7,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurface.withOpacity(0.06),
              borderRadius: BorderRadius.circular(3.5),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(3.5),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Bottom row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(pctLabel,
                  style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textTertiary(context))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isPositive
                          ? const Color(0xFF00C853)
                          : const Color(0xFFFF5252))
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  remaining,
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    color: isPositive
                        ? const Color(0xFF00C853)
                        : const Color(0xFFFF5252),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Shared mini transaction tile (matches TransactionTile) ─────────────────

class _MiniTxTile extends StatelessWidget {
  final String bank;
  final String category;
  final String amount;
  final Color amountColor;
  final String name;
  final bool isCategorized;
  final Color? categoryColor;

  const _MiniTxTile({
    required this.bank,
    required this.category,
    required this.amount,
    required this.amountColor,
    required this.name,
    this.isCategorized = true,
    this.categoryColor,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = categoryColor ?? amountColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Row(
        children: [
          // Left: bank name + category chip
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bank,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary(context))),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isCategorized ? chipColor.withOpacity(0.1) : null,
                    border: isCategorized
                        ? null
                        : Border.all(color: AppColors.textTertiary(context)),
                    borderRadius: BorderRadius.circular(isCategorized ? 5 : 6),
                  ),
                  child: Text(
                    category,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight:
                          isCategorized ? FontWeight.w700 : FontWeight.w600,
                      color: isCategorized
                          ? chipColor
                          : (AppColors.isDark(context)
                              ? AppColors.slate400
                              : AppColors.slate700),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Right: amount + counterparty name
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: amountColor)),
              const SizedBox(height: 2),
              Text(name,
                  style: TextStyle(
                      fontSize: 8,
                      color: AppColors.textSecondary(context),
                      letterSpacing: 0.4)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Tour bottom bar ────────────────────────────────────────────────────────

class _TourBottomBar extends StatelessWidget {
  final String title;
  final String description;
  final int highlightedNavIndex;
  final VoidCallback onNext;
  final VoidCallback onPrev;

  const _TourBottomBar({
    required this.title,
    required this.description,
    required this.highlightedNavIndex,
    required this.onNext,
    required this.onPrev,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        border: Border(
          top: BorderSide(color: AppColors.borderColor(context)),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10nText(title),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _CircleArrowButton(
                      icon: AppIcons.chevron_left, onTap: onPrev),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10nText(description),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CircleArrowButton(
                      icon: AppIcons.chevron_right, onTap: onNext),
                ],
              ),
              const SizedBox(height: 12),
              _MiniBottomNav(highlightedIndex: highlightedNavIndex),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.borderColor(context)),
          color: AppColors.cardColor(context),
        ),
        child: Icon(icon, size: 18, color: AppColors.textSecondary(context)),
      ),
    );
  }
}

/// Mini bottom nav shown in tour overlay – matches RedesignBottomNav.
class _MiniBottomNav extends StatelessWidget {
  final int highlightedIndex;

  const _MiniBottomNav({required this.highlightedIndex});

  static const _labels = ['Home', 'Money', 'Budget', 'Tools', 'You'];
  static const _icons = [
    AppIcons.home_outlined,
    AppIcons.account_balance_wallet_outlined,
    AppIcons.savings_outlined,
    AppIcons.grid_view_outlined,
    AppIcons.person_outline,
  ];
  static const _activeIcons = [
    AppIcons.home_filled,
    AppIcons.account_balance_wallet,
    AppIcons.savings,
    AppIcons.grid_view_rounded,
    AppIcons.person,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(5, (i) {
        final isActive = i == highlightedIndex;
        final color =
            isActive ? AppColors.primaryLight : AppColors.textTertiary(context);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? _activeIcons[i] : _icons[i],
              size: 18,
              color: color,
            ),
            const SizedBox(height: 2),
            Text(
              context.l10nText(_labels[i]),
              style: TextStyle(
                fontSize: 9,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: color,
              ),
            ),
            if (isActive) ...[
              const SizedBox(height: 2),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryLight,
                ),
              ),
            ],
          ],
        );
      }),
    );
  }
}

// ─── Screen 6: Add Your First Account ───────────────────────────────────────

class _AddAccountSlide extends StatefulWidget {
  final bool isActive;
  final VoidCallback onAddAccount;
  final VoidCallback onSkip;
  final VoidCallback onBack;

  const _AddAccountSlide({
    required this.isActive,
    required this.onAddAccount,
    required this.onSkip,
    required this.onBack,
  });

  @override
  State<_AddAccountSlide> createState() => _AddAccountSlideState();
}

class _AddAccountSlideState extends State<_AddAccountSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isActive) _ctrl.forward();
  }

  @override
  void didUpdateWidget(_AddAccountSlide old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _fadeSlide(double t, double begin, double end, Widget child) {
    final p = _progress(t, begin, end);
    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(0, 20 * (1 - p)),
        child: child,
      ),
    );
  }

  Widget _fadeScale(double t, double begin, double end, Widget child) {
    final p = _progress(t, begin, end);
    final sp = _progress(t, begin, end, Curves.easeOutBack);
    return Opacity(
      opacity: p,
      child: Transform.scale(scale: 0.5 + 0.5 * sp, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              _fadeScale(t, 0.0, 0.35,
                  Icon(AppIcons.add, size: 56, color: AppColors.primaryLight)),
              const SizedBox(height: 28),
              _fadeSlide(
                  t,
                  0.12,
                  0.45,
                  Text(
                    'Add Your First Account',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                  )),
              const SizedBox(height: 12),
              _fadeSlide(
                  t,
                  0.22,
                  0.55,
                  Text(
                    'Link a bank account so Totals can match your transactions. You can always add more later.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                      color: AppColors.textSecondary(context),
                    ),
                  )),
              const SizedBox(height: 32),
              _fadeSlide(
                  t,
                  0.40,
                  0.75,
                  SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: widget.onAddAccount,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          context.l10nText('Add Account'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.white,
                          ),
                        ),
                      ),
                    ),
                  )),
              const SizedBox(height: 16),
              _fadeSlide(
                  t,
                  0.55,
                  0.85,
                  GestureDetector(
                    onTap: () => widget.onSkip(),
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary(context),
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.textSecondary(context),
                      ),
                    ),
                  )),
              const Spacer(flex: 4),
              Opacity(
                opacity: _progress(t, 0.50, 0.90),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _CircleArrowButton(
                        icon: AppIcons.chevron_left, onTap: widget.onBack),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
