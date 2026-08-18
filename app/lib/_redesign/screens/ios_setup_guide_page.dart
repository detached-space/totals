import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/_redesign/theme/app_icons.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/utils/platform_support.dart';

/// iCloud "Add to Shortcuts" link for the ready-made Totals capture shortcut.
///
/// Opening this URL launches the Shortcuts app straight into the install sheet.
const String kTotalsShortcutUrl =
    'https://www.icloud.com/shortcuts/791a9d89a89a478e85cdd9a2254eacdd';

/// URL scheme that opens the Shortcuts app (for the manual automation step).
const String _kShortcutsAppUrl = 'shortcuts://';

/// SharedPreferences flag: the one-time iOS setup guide has been shown/dismissed.
const String _kIosSetupGuideCompletedKey = 'ios_setup_guide_completed';

/// Per-task completion, so a half-finished setup resumes where it left off.
const String _kTaskDonePrefix = 'ios_setup_task_';
const String _kAutomationStepsKey = 'ios_setup_automation_steps';

/// Checklist tasks, in the order they unlock. Each one gates the next.
const List<String> _kTaskIds = ['shortcut', 'automation'];

bool get _shortcutLinkConfigured => !kTotalsShortcutUrl.contains('REPLACE_WITH');

Future<bool> hasCompletedIosSetupGuide() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kIosSetupGuideCompletedKey) ?? false;
}

Future<void> markIosSetupGuideCompleted() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kIosSetupGuideCompletedKey, true);
}

/// Show the guide once on first launch (iOS only). No-op elsewhere or if the
/// user has already seen it.
Future<void> maybeShowIosSetupGuideOnFirstLaunch(BuildContext context) async {
  if (!PlatformSupport.usesFileInbox) return;
  if (await hasCompletedIosSetupGuide()) return;
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => const IosSetupGuidePage(firstRun: true),
      fullscreenDialog: true,
    ),
  );
}

/// Open the guide on demand (from Settings). Available any time.
Future<void> openIosSetupGuide(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const IosSetupGuidePage()),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Guide page
// ═════════════════════════════════════════════════════════════════════════════

class IosSetupGuidePage extends StatefulWidget {
  /// When true the page is shown as a one-time first-launch guide: no back
  /// button, and it only closes once every task has been checked off.
  final bool firstRun;

  const IosSetupGuidePage({super.key, this.firstRun = false});

  @override
  State<IosSetupGuidePage> createState() => _IosSetupGuidePageState();
}

class _IosSetupGuidePageState extends State<IosSetupGuidePage> {
  final Map<String, bool> _taskDone = {for (final id in _kTaskIds) id: false};
  final List<bool> _automationChecks =
      List<bool>.filled(_automationSteps.length, false);

  /// Task currently open in the accordion. Null means everything is collapsed.
  String? _expandedTask = _kTaskIds.first;

  @override
  void initState() {
    super.initState();
    _restoreProgress();
  }

  Future<void> _restoreProgress() async {
    final prefs = await SharedPreferences.getInstance();
    for (final id in _kTaskIds) {
      _taskDone[id] = prefs.getBool('$_kTaskDonePrefix$id') ?? false;
    }
    final saved = prefs.getStringList(_kAutomationStepsKey);
    if (saved != null) {
      for (var i = 0; i < _automationChecks.length && i < saved.length; i++) {
        _automationChecks[i] = saved[i] == '1';
      }
    }
    if (!mounted) return;
    setState(() => _expandedTask = _firstOpenTask());
  }

  // ── Checklist state ───────────────────────────────────────────────────────

  bool _isDone(String id) => _taskDone[id] ?? false;

  /// A task unlocks once the one before it is checked off.
  bool _isUnlocked(int index) => index == 0 || _isDone(_kTaskIds[index - 1]);

  /// First unlocked task that still needs doing — the one we auto-expand.
  String? _firstOpenTask() {
    for (var i = 0; i < _kTaskIds.length; i++) {
      if (_isUnlocked(i) && !_isDone(_kTaskIds[i])) return _kTaskIds[i];
    }
    return null;
  }

  int get _completedCount => _kTaskIds.where(_isDone).length;
  bool get _allDone => _completedCount == _kTaskIds.length;
  bool get _automationReady => !_automationChecks.contains(false);

  Future<void> _completeTask(String id) async {
    setState(() {
      _taskDone[id] = true;
      _expandedTask = _firstOpenTask();
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_kTaskDonePrefix$id', true);
  }

  void _toggleTask(int index) {
    if (!_isUnlocked(index)) return;
    final id = _kTaskIds[index];
    setState(() => _expandedTask = _expandedTask == id ? null : id);
  }

  Future<void> _toggleAutomationStep(int index) async {
    setState(() => _automationChecks[index] = !_automationChecks[index]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kAutomationStepsKey,
      _automationChecks.map((checked) => checked ? '1' : '0').toList(),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {/* fall through */}
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(context.l10nTextRead('Could not open the Shortcuts app.')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _installShortcut() async {
    if (!_shortcutLinkConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context
              .l10nTextRead('The Totals shortcut link is not set up yet.')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _launch(kTotalsShortcutUrl);
  }

  Future<void> _finish() async {
    await markIosSetupGuideCompleted();
    if (mounted) Navigator.of(context).maybePop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstRun = widget.firstRun;

    return PopScope(
      canPop: !firstRun || _allDone,
      child: Scaffold(
        backgroundColor: AppColors.background(context),
        appBar: AppBar(
          backgroundColor: AppColors.background(context),
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: !firstRun,
          leading: firstRun
              ? null
              : IconButton(
                  icon: Icon(AppIcons.arrow_back_rounded,
                      color: AppColors.textPrimary(context)),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
          title: Text(
            context.l10nText('Automatic tracking'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary(context),
            ),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Hero ──
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: SvgPicture.asset(
                            'assets/images/logo.svg',
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.l10nText('Track transactions automatically'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        context.l10nText(
                          'iPhone can\'t read bank SMS directly, so Totals connects them with a Shortcut and a Messages automation. It takes about a minute, and you only set it up once.',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),

                      _SetupProgress(
                        completed: _completedCount,
                        total: _kTaskIds.length,
                      ),
                      const SizedBox(height: 16),

                      // ── Task 1: install the shortcut ──
                      _TaskCard(
                        step: 1,
                        title: context.l10nText('Install the Totals shortcut'),
                        subtitle: context
                            .l10nText('Adds the ready-made capture shortcut'),
                        done: _isDone('shortcut'),
                        locked: !_isUnlocked(0),
                        expanded: _expandedTask == 'shortcut',
                        onToggle: () => _toggleTask(0),
                        child: _buildShortcutBody(theme),
                      ),
                      const SizedBox(height: 12),

                      // ── Task 2: create the automation ──
                      _TaskCard(
                        step: 2,
                        title:
                            context.l10nText('Create the Messages automation'),
                        subtitle: context
                            .l10nText('Hands new bank SMS to Totals for you'),
                        done: _isDone('automation'),
                        locked: !_isUnlocked(1),
                        expanded: _expandedTask == 'automation',
                        onToggle: () => _toggleTask(1),
                        child: _buildAutomationBody(theme),
                      ),
                      const SizedBox(height: 16),

                      _NoteCallout(
                        icon: AppIcons.info_outline_rounded,
                        color: AppColors.primaryLight,
                        text: context.l10nText(
                          'New transactions appear when you open Totals. Add your bank account in Totals first so it can recognize the messages.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Footer ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (firstRun && !_allDone) ? null : _finish,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryDark,
                          foregroundColor: AppColors.white,
                          disabledBackgroundColor: AppColors.textTertiary(context)
                              .withValues(alpha: 0.15),
                          disabledForegroundColor:
                              AppColors.textTertiary(context),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          firstRun
                              ? context.l10nText('Finish setup')
                              : context.l10nText('Got it'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (firstRun) ...[
                      const SizedBox(height: 8),
                      Text(
                        _allDone
                            ? context.l10nText('You\'re all set.')
                            : context.l10nText(
                                'Check off both steps to continue.'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _allDone
                              ? AppColors.primaryLight
                              : AppColors.textTertiary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutBody(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10nText(
            'Add the ready-made shortcut. The button opens the Shortcuts app. Scroll down and tap "Add Shortcut" to install it.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary(context),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        for (int i = 0; i < _shortcutSteps.length; i++)
          _SubStep(
            index: i + 1,
            text: context.l10nText(_shortcutSteps[i]),
            isLast: i == _shortcutSteps.length - 1,
          ),
        const SizedBox(height: 14),
        _ActionButton(
          icon: AppIcons.download_rounded,
          label: context.l10nText('Add Totals Shortcut'),
          onTap: _installShortcut,
        ),
        const SizedBox(height: 8),
        _DoneButton(
          label: context.l10nText('I installed the shortcut'),
          onTap: () => _completeTask('shortcut'),
        ),
      ],
    );
  }

  Widget _buildAutomationBody(ThemeData theme) {
    final remaining = _automationChecks.where((checked) => !checked).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10nText(
            'iOS won\'t let Totals set this up for you, so create it once by hand. Tap each step as you finish it:',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary(context),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < _automationSteps.length; i++)
          _CheckableStep(
            index: i + 1,
            text: context.l10nText(_automationSteps[i]),
            checked: _automationChecks[i],
            onTap: () => _toggleAutomationStep(i),
          ),
        const SizedBox(height: 12),
        _NoteCallout(
          icon: AppIcons.info_outline_rounded,
          color: AppColors.amber,
          text: context.l10nText(
            'Already tried setting up Totals? Delete any old Totals automation first, or messages may be counted twice.',
          ),
        ),
        const SizedBox(height: 14),
        _ActionButton(
          icon: AppIcons.sms_outlined,
          label: context.l10nText('Open Shortcuts app'),
          filled: false,
          onTap: () => _launch(_kShortcutsAppUrl),
        ),
        const SizedBox(height: 8),
        _DoneButton(
          label: _automationReady
              ? context.l10nText('The automation is ready')
              : '${context.l10nText('Tick every step first')} ($remaining)',
          onTap:
              _automationReady ? () => _completeTask('automation') : null,
        ),
      ],
    );
  }
}

/// Shortcut-install walkthrough (kept as fallbacks so l10n can override).
const List<String> _shortcutSteps = [
  'Tap "Add Totals Shortcut" below.',
  'The Shortcuts app opens on the ready-made shortcut.',
  'Scroll down and tap Add Shortcut.',
  'Come back here and mark this step done.',
];

/// Automation walkthrough sub-steps (kept as fallbacks so l10n can override).
const List<String> _automationSteps = [
  'In the Shortcuts app, open the Automation tab, then tap ＋ → New Automation.',
  'Choose Message.',
  'Set Sender to Any, turn on Message Contains, and type ETB.',
  'Select Run Immediately, then tap Next.',
  'Choose the Totals shortcut you installed in Step 1.',
  'Tap Done. You\'re set.',
];

// ═════════════════════════════════════════════════════════════════════════════
// Building blocks
// ═════════════════════════════════════════════════════════════════════════════

/// Thin "N of M done" bar above the checklist.
class _SetupProgress extends StatelessWidget {
  final int completed;
  final int total;

  const _SetupProgress({required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDone = completed == total;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: total == 0 ? 0 : completed / total),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor:
                    AppColors.primaryLight.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(
                  allDone ? AppColors.primaryDark : AppColors.primaryLight,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$completed/$total',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: allDone ? AppColors.primaryDark : AppColors.primaryLight,
          ),
        ),
      ],
    );
  }
}

/// One expandable checklist task. Locked until the task before it is done.
class _TaskCard extends StatelessWidget {
  final int step;
  final String title;
  final String subtitle;
  final bool done;
  final bool locked;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _TaskCard({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.locked,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  Widget _statusDot(BuildContext context) {
    if (done) {
      return Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          color: AppColors.primaryDark,
          shape: BoxShape.circle,
        ),
        child: const Icon(AppIcons.check_rounded,
            size: 17, color: AppColors.white),
      );
    }
    if (locked) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.textTertiary(context).withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(AppIcons.lock_outline_rounded,
            size: 15, color: AppColors.textTertiary(context)),
      );
    }
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        color: AppColors.primaryDark,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$step',
          style: const TextStyle(
            color: AppColors.white,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedOpacity(
      opacity: locked ? 0.5 : 1,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.cardColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: done
                ? AppColors.primaryLight.withValues(alpha: 0.3)
                : expanded
                    ? AppColors.primaryLight.withValues(alpha: 0.5)
                    : AppColors.borderColor(context),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: locked ? null : onToggle,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _statusDot(context),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              locked
                                  ? context.l10nText('Finish the step above first')
                                  : subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textTertiary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!locked)
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            AppIcons.expand_more,
                            size: 18,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: child,
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
              sizeCurve: Curves.easeInOutCubic,
            ),
          ],
        ),
      ),
    );
  }
}

/// A sub-step the user ticks off one at a time.
class _CheckableStep extends StatelessWidget {
  final int index;
  final String text;
  final bool checked;
  final VoidCallback onTap;

  const _CheckableStep({
    required this.index,
    required this.text,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checked ? AppColors.primaryLight : Colors.transparent,
                  border: Border.all(
                    color: checked
                        ? AppColors.primaryLight
                        : AppColors.textTertiary(context)
                            .withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
                child: checked
                    ? const Icon(AppIcons.check_rounded,
                        size: 13, color: AppColors.white)
                    : Center(
                        child: Text(
                          '$index',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: checked
                          ? AppColors.textTertiary(context)
                          : AppColors.textPrimary(context),
                      height: 1.45,
                    ),
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

class _SubStep extends StatelessWidget {
  final int index;
  final String text;
  final bool isLast;

  const _SubStep({
    required this.index,
    required this.text,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary(context),
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCallout extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _NoteCallout({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary(context),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryLight,
            foregroundColor: AppColors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: AppColors.primaryLight),
        label: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.primaryLight,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          side: BorderSide(color: AppColors.primaryLight.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Low-weight "check this task off" control — a tonal indigo pill, deliberately
/// quieter than the task's own action button. A null [onTap] disables it.
class _DoneButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _DoneButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(AppIcons.check_rounded,
            size: 15,
            color: enabled
                ? AppColors.primaryLight
                : AppColors.textTertiary(context)),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: enabled
                ? AppColors.primaryLight
                : AppColors.textTertiary(context),
          ),
        ),
        style: TextButton.styleFrom(
          backgroundColor: enabled
              ? AppColors.primaryLight.withValues(alpha: 0.1)
              : AppColors.textTertiary(context).withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}
