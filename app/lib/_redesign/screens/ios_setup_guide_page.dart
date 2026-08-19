import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:totals/_redesign/screens/ios_backup_import_flow.dart';
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

/// SharedPreferences flag: the one-time iOS setup flow has been completed.
const String _kIosSetupGuideCompletedKey = 'ios_setup_guide_completed';

/// Remembers the returning-vs-new answer so reopening resumes the same track.
const String _kIosSetupReturningKey = 'ios_setup_is_returning_user';

/// Base URL for the step clips. Each step appends `<id>.mp4` / `<id>.jpg`.
///
/// PLACEHOLDER — swap for the real Cloudflare origin once the Figma clips are
/// exported. Nothing here blocks a step: the poster lazy-loads, and when it
/// fails the step falls back to its icon. The instructions live in the text.
const String kSetupMediaBaseUrl = 'https://media.example.invalid/totals/setup';

bool get _shortcutLinkConfigured => !kTotalsShortcutUrl.contains('REPLACE_WITH');

Future<bool> hasCompletedIosSetupGuide() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kIosSetupGuideCompletedKey) ?? false;
}

Future<void> markIosSetupGuideCompleted() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kIosSetupGuideCompletedKey, true);
}

/// Show the setup flow once on first launch (iOS only). No-op elsewhere or if
/// the user has already been through it.
Future<void> maybeShowIosSetupGuideOnFirstLaunch(BuildContext context) async {
  if (!PlatformSupport.usesFileInbox) return;
  if (await hasCompletedIosSetupGuide()) return;
  if (!context.mounted) return;
  await showIosSetupSheet(context, firstRun: true);
}

/// Open the setup flow on demand (from Settings). Dismissible.
Future<void> openIosSetupGuide(BuildContext context) =>
    showIosSetupSheet(context, firstRun: false);

/// The migration step on its own: same clip-and-action sheet, one page, so
/// importing from the Scriptable version is guided rather than dumping the user
/// straight into a file picker.
Future<void> openIosImportGuide(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _IosSetupSheet(
      firstRun: false,
      fixedSteps: [_importStep],
    ),
  );
}

/// The setup flow itself: a tall bottom sheet, one step per page.
///
/// On [firstRun] it cannot be dismissed by drag, scrim tap or back gesture —
/// a half-configured setup leaves the app looking broken, which is the failure
/// this flow exists to prevent. It still always exits from the last step, so a
/// reviewer is never trapped.
Future<void> showIosSetupSheet(
  BuildContext context, {
  required bool firstRun,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: !firstRun,
    enableDrag: !firstRun,
    backgroundColor: Colors.transparent,
    builder: (_) => _IosSetupSheet(firstRun: firstRun),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Steps
// ═════════════════════════════════════════════════════════════════════════════

/// What a step's button does when tapped. Never gated on media loading.
enum _StepActionKind { none, installShortcut, openShortcuts, importBackup }

class _SetupStep {
  /// Also the media file stem: `<id>.mp4` / `<id>.jpg`.
  final String id;
  final String title;
  final String body;
  final IconData icon;
  final String? actionLabel;
  final _StepActionKind action;

  const _SetupStep({
    required this.id,
    required this.title,
    required this.body,
    required this.icon,
    this.actionLabel,
    this.action = _StepActionKind.none,
  });
}

/// Shared tail: both tracks end by installing the shortcut and wiring the
/// automation. Returning users reach it after their data is safely across.
const List<_SetupStep> _commonSteps = [
  _SetupStep(
    id: 'install-shortcut',
    title: 'Install the Totals Sync shortcut',
    body:
        'This is the shortcut that reads a bank SMS and hands it to Totals. The '
        'button opens Shortcuts. Scroll down and tap "Add Shortcut".',
    icon: AppIcons.download_rounded,
    actionLabel: 'Add Totals Shortcut',
    action: _StepActionKind.installShortcut,
  ),
  _SetupStep(
    id: 'automation',
    title: 'Create the Messages automation',
    body:
        'In Shortcuts, open Automation → New Automation → Message. Set Sender to '
        'Any, turn on Message Contains and type ETB, choose Run Immediately, then '
        'pick the Totals Sync shortcut.',
    icon: AppIcons.sms_outlined,
    actionLabel: 'Open Shortcuts app',
    action: _StepActionKind.openShortcuts,
  ),
];

/// Fresh install: nothing to migrate, nothing to clean up.
const List<_SetupStep> _newUserSteps = _commonSteps;

/// Coming from the Scriptable version. Data first — moving their history across
/// before the fiddly Shortcuts work buys patience for the rest — then remove the
/// old automation so incoming SMS aren't captured twice.
const _SetupStep _importStep = _SetupStep(
  id: 'import-backup',
    title: 'Bring your data across',
  body: 'Your old data is already on your phone, in iCloud Drive → Scriptable. '
      'Select ALL the files in that folder, not just transactions.txt. '
      'Leaving out profiles.txt or account_overrides.txt imports silently '
      'wrong: no profiles, and your accounts split incorrectly.',
  icon: AppIcons.download_rounded,
  actionLabel: 'Choose your Scriptable files',
  action: _StepActionKind.importBackup,
);

const List<_SetupStep> _returningUserSteps = [
  _importStep,
  _SetupStep(
    id: 'remove-automation',
    title: 'Remove your old Totals automation',
    body:
        'In Shortcuts → Automation, delete any automation pointing at the old '
        'Totals or Scriptable. If it stays, every bank SMS gets captured twice.',
    icon: AppIcons.delete_outline_rounded,
    actionLabel: 'Open Shortcuts app',
    action: _StepActionKind.openShortcuts,
  ),
  ..._commonSteps,
];

// ═════════════════════════════════════════════════════════════════════════════
// Sheet
// ═════════════════════════════════════════════════════════════════════════════

class _IosSetupSheet extends StatefulWidget {
  final bool firstRun;

  /// When set, the branch question is skipped and these steps are shown as-is.
  /// Used for single-topic sheets opened from Discover Totals.
  final List<_SetupStep>? fixedSteps;

  const _IosSetupSheet({required this.firstRun, this.fixedSteps});

  @override
  State<_IosSetupSheet> createState() => _IosSetupSheetState();
}

class _IosSetupSheetState extends State<_IosSetupSheet> {
  final PageController _pager = PageController();

  /// null until the branch question is answered.
  bool? _isReturningUser;
  int _index = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_kIosSetupReturningKey);
    if (!mounted || saved == null) return;
    setState(() => _isReturningUser = saved);
  }

  List<_SetupStep> get _steps =>
      widget.fixedSteps ??
      ((_isReturningUser ?? false) ? _returningUserSteps : _newUserSteps);

  bool get _onLastStep => _index >= _steps.length - 1;

  Future<void> _chooseTrack(bool returning) async {
    setState(() {
      _isReturningUser = returning;
      _index = 0;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIosSetupReturningKey, returning);
  }

  void _next() {
    if (_onLastStep) {
      _finish();
      return;
    }
    _pager.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() {
    if (_index == 0 && widget.fixedSteps != null) {
      Navigator.of(context).pop();
      return;
    }
    if (_index == 0) {
      // Back out of the track choice rather than closing the sheet.
      setState(() => _isReturningUser = null);
      return;
    }
    _pager.previousPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    // A single-topic sheet is not the setup flow; finishing it must not mark
    // first-run setup as done.
    if (widget.fixedSteps == null) await markIosSetupGuideCompleted();
    // pop, not maybePop: on first run PopScope sets canPop false to block the
    // back gesture, and maybePop honours that, so Done would do nothing.
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {/* fall through */}
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) _snack(context.l10nTextRead('Could not open Shortcuts.'));
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _runAction(_SetupStep step) async {
    switch (step.action) {
      case _StepActionKind.none:
        return;
      case _StepActionKind.openShortcuts:
        await _launch(_kShortcutsAppUrl);
      case _StepActionKind.installShortcut:
        if (!_shortcutLinkConfigured) {
          _snack(context
              .l10nTextRead('The Totals shortcut link is not set up yet.'));
          return;
        }
        await _launch(kTotalsShortcutUrl);
      case _StepActionKind.importBackup:
        setState(() => _busy = true);
        try {
          await runIosBackupImport(context);
        } catch (error) {
          if (mounted) {
            _snack('${context.l10nTextRead('Migration failed')}: $error');
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    // The branch question is two buttons and a sentence — at step height it
    // reads as an empty screen. Grow into the tall sheet only once there's a
    // clip to show.
    final heightFactor =
        (_isReturningUser == null && widget.fixedSteps == null) ? 0.52 : 0.82;

    return PopScope(
      // A half-configured setup leaves the app looking empty and broken, so the
      // first run only exits from the last step.
      canPop: !widget.firstRun,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        height: media.size.height * heightFactor,
        // Clipped rather than decorated: the clip runs edge to edge and has to
        // be cut by the sheet's own top corners.
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.background(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: (_isReturningUser == null && widget.fixedSteps == null)
            ? SafeArea(top: false, child: _buildTrackQuestion(context))
            : _buildSteps(context),
      ),
    );
  }

  // ── Branch question ───────────────────────────────────────────────────────

  Widget _buildTrackQuestion(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Column(
        children: [
          _Grabber(visible: !widget.firstRun),
          const Spacer(),
          // The app icon, not assets/images/logo.svg: that SVG is an Illustrator
          // export whose styles are DTD entities (style="&st2;"), which
          // flutter_svg does not resolve, so it renders blank.
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/icon/totals_icon.png',
              width: 72,
              height: 72,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.l10nText('Set up automatic tracking'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10nText(
              'iPhone can\'t read bank SMS directly, so Totals connects them with '
              'a Shortcut. First, have you used Totals before, including the '
              'Scriptable version?',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary(context),
              height: 1.5,
            ),
          ),
          const Spacer(),
          _PrimaryButton(
            label: context.l10nText('Yes, I\'m moving my data over'),
            onTap: () => _chooseTrack(true),
          ),
          const SizedBox(height: 10),
          _SecondaryButton(
            label: context.l10nText('No, this is my first time'),
            onTap: () => _chooseTrack(false),
          ),
        ],
      ),
    );
  }

  // ── Steps ─────────────────────────────────────────────────────────────────

  Widget _buildSteps(BuildContext context) {
    final theme = Theme.of(context);
    final steps = _steps;
    final step = steps[_index.clamp(0, steps.length - 1)];

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pager,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: steps.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => _StepView(
              step: steps[i],
              onBack: _busy ? null : _back,
            ),
          ),
        ),
        _PageDots(count: steps.length, index: _index),
        const SizedBox(height: 6),
        Text(
          '${context.l10nText('Step')} ${_index + 1} ${context.l10nText('of')} ${steps.length}',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary(context),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            children: [
              if (step.actionLabel != null) ...[
                _PrimaryButton(
                  label: context.l10nText(step.actionLabel!),
                  busy: _busy,
                  onTap: _busy ? null : () => _runAction(step),
                ),
                const SizedBox(height: 10),
                _SecondaryButton(
                  label: _onLastStep
                      ? context.l10nText('Done')
                      : context.l10nText('Next'),
                  onTap: _busy ? null : _next,
                ),
              ] else
                _PrimaryButton(
                  label: _onLastStep
                      ? context.l10nText('Done')
                      : context.l10nText('Next'),
                  onTap: _busy ? null : _next,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Pieces
// ═════════════════════════════════════════════════════════════════════════════

class _StepView extends StatelessWidget {
  final _SetupStep step;
  final VoidCallback? onBack;

  const _StepView({required this.step, this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The clip runs edge to edge with no padding of its own — the sheet's top
    // corners do the clipping.
    //
    // The copy is a non-flex child so it takes only the height it needs and the
    // clip absorbs everything left over; splitting fixed shares left a dead band
    // under short steps. Capped and scrollable so a long step can't push the
    // clip out on a small screen.
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _StepMedia(step: step)),
                if (onBack != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _MediaBackButton(onTap: onBack!),
                  ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.5),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
              child: Column(
                children: [
                  Text(
                    context.l10nText(step.title),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.l10nText(step.body),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary(context),
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sits on the clip rather than in a header row, so the sheet keeps its height
/// for content.
class _MediaBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _MediaBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background(context).withValues(alpha: 0.85),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            AppIcons.chevron_left,
            size: 20,
            color: AppColors.textPrimary(context),
          ),
        ),
      ),
    );
  }
}

/// The clip area. Today it renders the placeholder; when the real poster URL is
/// live this lazy-loads it and still degrades to the icon on any failure, so a
/// dead CDN can never block a non-dismissible step.
class _StepMedia extends StatelessWidget {
  final _SetupStep step;

  const _StepMedia({required this.step});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryLight.withValues(alpha: 0.07),
      child: Image.network(
        '$kSetupMediaBaseUrl/${step.id}.jpg',
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : _placeholder(context),
        errorBuilder: (context, _, __) => _placeholder(context),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(step.icon, size: 44, color: AppColors.primaryLight),
          const SizedBox(height: 12),
          Text(
            context.l10nText('Walkthrough clip'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppColors.primaryLight,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int index;

  const _PageDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index
                  ? AppColors.primaryLight
                  : AppColors.primaryLight.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

/// Only drawn when the sheet can actually be dragged — a grabber on a
/// non-dismissible sheet invites a swipe that does nothing.
class _Grabber extends StatelessWidget {
  final bool visible;

  const _Grabber({this.visible = true});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(height: 14);
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.textTertiary(context).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  const _PrimaryButton({required this.label, this.onTap, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryDark,
          foregroundColor: AppColors.white,
          disabledBackgroundColor:
              AppColors.textTertiary(context).withValues(alpha: 0.15),
          disabledForegroundColor: AppColors.textTertiary(context),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _SecondaryButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryLight,
          ),
        ),
      ),
    );
  }
}
