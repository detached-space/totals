import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:totals/_redesign/theme/app_colors.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/services/shared_expense_recovery_code.dart';
import 'package:totals/services/shared_expense_vault.dart';
import 'package:totals/services/shared_expense_vault_service.dart';

const int _minPinLength = 6;

// =============================================================================
// Entry points: callers use these instead of constructing the sheets directly.
// =============================================================================

/// Open the first-time setup flow: ask for a PIN, generate the recovery code,
/// upload the sealed vault, then display the recovery code for the user to
/// save. Returns the recovery code on success, null if the user dismissed.
Future<String?> showVaultSetupSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background(context),
    barrierColor: AppColors.black.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _VaultSetupSheet(),
  );
}

/// Open the unlock flow: ask for the PIN, derive KEK in memory so subsequent
/// vault sync calls actually upload. Returns true on success.
Future<bool> showVaultUnlockSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background(context),
    barrierColor: AppColors.black.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _VaultUnlockSheet(),
  );
  return result ?? false;
}

/// Open the restore flow: ask for a recovery code + PIN, fetch the vault,
/// decrypt, write seed and group keys into local storage. Returns true on
/// success — the caller is responsible for any follow-up refresh that
/// populates the local DB rows.
Future<bool> showVaultRestoreSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background(context),
    barrierColor: AppColors.black.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _VaultRestoreSheet(),
  );
  return result ?? false;
}

/// Open the change-PIN flow: old PIN → new PIN twice → re-seal + upload.
/// Returns true on success.
Future<bool> showVaultChangePinSheet(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background(context),
    barrierColor: AppColors.black.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _VaultChangePinSheet(),
  );
  return result ?? false;
}

/// Show the user their recovery code in a read-only sheet so they can
/// re-copy it.
Future<void> showVaultRecoveryCodeSheet(BuildContext context) async {
  final code = SharedExpenseVaultService.instance.recoveryCode;
  if (code == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background(context),
    barrierColor: AppColors.black.withValues(alpha: 0.5),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _VaultRecoveryCodeSheet(code: code),
  );
}

// =============================================================================
// Shared shell.
// =============================================================================

class _SheetShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _SheetShell({
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    // Lift the entire sheet above the keyboard, with a little extra
    // breathing room so the primary action isn't kissing the keyboard.
    // Mirrors the expense-add sheet's approach so the two flows feel
    // consistent.
    final keyboardLift = keyboardInset > 0 ? keyboardInset + 24 : 0.0;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardLift),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderColor(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final bool autofocus;
  final void Function(String)? onSubmitted;
  const _PinField({
    required this.controller,
    required this.hint,
    this.focusNode,
    this.autofocus = false,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(12),
      ],
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.cardColor(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryLight),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryLight,
          foregroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

String _pinMinMessage(BuildContext context) {
  return context
      .l10nRead('vault.pinMinDigits', 'PIN must be at least {count} digits.')
      .replaceAll('{count}', '$_minPinLength');
}

String _failureMessage(
  BuildContext context,
  String key,
  String fallback,
  Object error,
) {
  return context.l10nRead(key, fallback).replaceAll('{error}', '$error');
}

/// Format the "vault is locked" message — shown after too many wrong-PIN
/// attempts pile up server-side. We try to be specific about how long the
/// wait is, since that's the actual question the user will ask.
String _lockedMessage(BuildContext context, DateTime? lockedUntil) {
  if (lockedUntil == null) {
    return context.l10nRead(
      'vault.tooManyWrongPinsHour',
      'Too many wrong PINs. Try again in an hour.',
    );
  }
  final remaining = lockedUntil.difference(DateTime.now());
  if (remaining.isNegative) {
    return context.l10nRead(
      'vault.lockoutJustLifted',
      'Lockout just lifted — try again.',
    );
  }
  if (remaining.inMinutes < 2) {
    return context.l10nRead(
      'vault.lockedMinute',
      'Locked. Try again in a minute.',
    );
  }
  if (remaining.inMinutes < 60) {
    return context
        .l10nRead(
          'vault.lockedMinutes',
          'Locked. Try again in {count} minutes.',
        )
        .replaceAll('{count}', '${remaining.inMinutes}');
  }
  final hours = (remaining.inMinutes / 60).ceil();
  final unit = hours == 1 ? 'hour' : 'hours';
  return context
      .l10nRead('vault.lockedHours', 'Locked. Try again in {count} $unit.')
      .replaceAll('{count}', '$hours');
}

class _ErrorText extends StatelessWidget {
  final String text;
  const _ErrorText(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.red,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// =============================================================================
// Status banner — shows up on the shared expenses page when the vault
// needs the user's attention (set-up needed, or unlock needed). The
// service is a ChangeNotifier so we rebuild automatically.
// =============================================================================

/// Banner that prompts the user to set up or unlock their vault. Returns an
/// empty widget when no action is needed (no vault yet AND no groups, OR
/// vault is set up and unlocked).
class SharedExpenseVaultBanner extends StatelessWidget {
  /// Whether the user currently has any groups on this device. We don't push
  /// vault setup until they actually have something worth backing up.
  final bool hasGroups;
  const SharedExpenseVaultBanner({super.key, required this.hasGroups});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SharedExpenseVaultService.instance,
      builder: (context, _) {
        final service = SharedExpenseVaultService.instance;
        if (service.hasVault && service.isUnlocked) {
          return const SizedBox.shrink();
        }
        if (!service.hasVault && !hasGroups) {
          return const SizedBox.shrink();
        }
        final isSetup = !service.hasVault;
        final label = isSetup
            ? context.l10nText('Back up your shared expense identity')
            : context.l10nText('Unlock backup');
        final detail = isSetup
            ? context.l10nText(
                'Set a PIN so you can restore your groups on a new phone.',
              )
            : context.l10nText(
                'Enter your PIN once to resume automatic backup.',
              );
        final action = isSetup
            ? context.l10nText('Set up')
            : context.l10nText('Unlock');
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.amber.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, color: AppColors.amber, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  if (isSetup) {
                    showVaultSetupSheet(context);
                  } else {
                    showVaultUnlockSheet(context);
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.amber,
                  textStyle:
                      const TextStyle(fontWeight: FontWeight.w800),
                ),
                child: Text(action),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// DEBUG-ONLY: shows the current vault state and a "Clear backup setup"
/// button so a tester can reset the vault without going through device
/// settings. Returns an empty widget in release builds.
class SharedExpenseVaultDebugRow extends StatelessWidget {
  const SharedExpenseVaultDebugRow({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: SharedExpenseVaultService.instance,
      builder: (context, _) {
        final service = SharedExpenseVaultService.instance;
        final stateLabel = !service.hasVault
            ? 'no vault'
            : service.isUnlocked
                ? 'unlocked'
                : 'locked';
        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: AppColors.borderColor(context).withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.borderColor(context),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.bug_report_outlined,
                size: 16,
                color: AppColors.textSecondary(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Vault debug — state: $stateLabel'
                  '${service.recoveryCode != null ? ' • code: ${service.recoveryCode!.substring(0, 6)}…' : ''}',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (service.hasVault)
                TextButton(
                  onPressed: () => _confirmReset(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.red,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  child: const Text('Clear'),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear backup setup?'),
        content: const Text(
          'Wipes the local recovery code so the next launch behaves like a '
          'fresh install. The server-side vault row stays but is unreachable '
          '— no code to fetch it with. Debug only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SharedExpenseVaultService.instance.debugReset();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Vault cleared locally.')),
    );
  }
}

/// Link that opens the restore flow. The empty state surfaces this so a
/// fresh install with no groups yet can recover their previous identity.
class SharedExpenseVaultRestoreLink extends StatelessWidget {
  const SharedExpenseVaultRestoreLink({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SharedExpenseVaultService.instance,
      builder: (context, _) {
        if (SharedExpenseVaultService.instance.hasVault) {
          return const SizedBox.shrink();
        }
        return TextButton.icon(
          onPressed: () => showVaultRestoreSheet(context),
          icon: const Icon(Icons.restore, size: 18),
          label: Text(context.l10nText('Restore from another device')),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryLight,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Setup sheet.
// =============================================================================

class _VaultSetupSheet extends StatefulWidget {
  const _VaultSetupSheet();

  @override
  State<_VaultSetupSheet> createState() => _VaultSetupSheetState();
}

enum _SetupStep { pin, confirm, success }

class _VaultSetupSheetState extends State<_VaultSetupSheet> {
  final _firstPinController = TextEditingController();
  final _secondPinController = TextEditingController();
  final _secondPinFocus = FocusNode();

  _SetupStep _step = _SetupStep.pin;
  bool _busy = false;
  String? _error;
  String? _recoveryCode;
  String _pinBuffer = '';

  @override
  void dispose() {
    _firstPinController.dispose();
    _secondPinController.dispose();
    _secondPinFocus.dispose();
    super.dispose();
  }

  void _advanceToConfirm() {
    final pin = _firstPinController.text.trim();
    if (pin.length < _minPinLength) {
      setState(() {
        _error = _pinMinMessage(context);
      });
      return;
    }
    setState(() {
      _pinBuffer = pin;
      _error = null;
      _step = _SetupStep.confirm;
    });
    // Autofocus on a freshly-rendered field is unreliable when the parent
    // rebuilds with a different child — Flutter sometimes reuses the
    // element and skips the autofocus. Request focus after the next
    // frame to avoid that race.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _secondPinFocus.requestFocus();
    });
  }

  Future<void> _confirmAndUpload() async {
    final second = _secondPinController.text.trim();
    if (second != _pinBuffer) {
      setState(() {
        _error = context.l10nRead(
          'vault.pinMismatch',
          'PINs don\'t match. Try again.',
        );
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await SharedExpenseVaultService.instance.setupNew(
        pin: _pinBuffer,
      );
      if (!mounted) return;
      setState(() {
        _recoveryCode = code;
        _step = _SetupStep.success;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _failureMessage(
          context,
          'vault.setupFailed',
          'Couldn\'t set up backup: {error}',
          error,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _SetupStep.pin:
        return _SheetShell(
          title: context.l10nText('Back up your shared expense identity'),
          subtitle: context.l10nText(
            'Pick a PIN. We use it to encrypt your backup. We can\'t recover it if you forget.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PinField(
                controller: _firstPinController,
                hint: context.l10nText('Enter PIN'),
                autofocus: true,
                onSubmitted: (_) => _advanceToConfirm(),
              ),
              if (_error != null) _ErrorText(_error!),
              const SizedBox(height: 16),
              _PrimaryButton(
                label: context.l10nText('Continue'),
                busy: _busy,
                onPressed: _advanceToConfirm,
              ),
            ],
          ),
        );
      case _SetupStep.confirm:
        return _SheetShell(
          title: context.l10nText('Confirm your PIN'),
          subtitle: context.l10nText('Type it once more.'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PinField(
                controller: _secondPinController,
                focusNode: _secondPinFocus,
                hint: context.l10nText('Confirm PIN'),
                autofocus: true,
                onSubmitted: (_) => _confirmAndUpload(),
              ),
              if (_error != null) _ErrorText(_error!),
              const SizedBox(height: 16),
              _PrimaryButton(
                label: context.l10nText('Set up backup'),
                busy: _busy,
                onPressed: _confirmAndUpload,
              ),
            ],
          ),
        );
      case _SetupStep.success:
        return _SheetShell(
          title: context.l10nText('Save this code'),
          subtitle: context.l10nText(
            'You\'ll need this code plus your PIN to restore on a new device.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RecoveryCodeDisplay(code: _recoveryCode!),
              const SizedBox(height: 20),
              _PrimaryButton(
                label: context.l10nText('I saved it'),
                busy: false,
                onPressed: () => Navigator.of(context).pop(_recoveryCode),
              ),
            ],
          ),
        );
    }
  }
}

class _RecoveryCodeDisplay extends StatelessWidget {
  final String code;
  const _RecoveryCodeDisplay({required this.code});

  @override
  Widget build(BuildContext context) {
    final pretty = SharedExpenseRecoveryCode.format(code);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            pretty,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary(context),
              fontFamily: 'monospace',
              letterSpacing: 2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: pretty));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(context.l10nText('Recovery code copied')),
                ),
              );
            },
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: Text(context.l10nText('Copy code')),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Unlock sheet.
// =============================================================================

class _VaultUnlockSheet extends StatefulWidget {
  const _VaultUnlockSheet();

  @override
  State<_VaultUnlockSheet> createState() => _VaultUnlockSheetState();
}

class _VaultUnlockSheetState extends State<_VaultUnlockSheet> {
  final _pinController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.length < _minPinLength) {
      setState(() => _error = _pinMinMessage(context));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SharedExpenseVaultService.instance.unlock(pin: pin);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SharedExpenseVaultWrongPinException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10nRead(
          'vault.wrongPinTryAgain',
          'Wrong PIN. Try again.',
        );
      });
    } on SharedExpenseVaultLockedException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _lockedMessage(context, error.lockedUntil);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _failureMessage(
          context,
          'vault.unlockFailed',
          'Couldn\'t unlock: {error}',
          error,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: context.l10nText('Unlock backup'),
      subtitle: context.l10nText(
        'Enter your PIN to resume backing up your shared expense changes.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PinField(
            controller: _pinController,
            hint: context.l10nText('Enter PIN'),
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) _ErrorText(_error!),
          const SizedBox(height: 16),
          _PrimaryButton(
            label: context.l10nText('Unlock'),
            busy: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Restore sheet.
// =============================================================================

class _VaultRestoreSheet extends StatefulWidget {
  const _VaultRestoreSheet();

  @override
  State<_VaultRestoreSheet> createState() => _VaultRestoreSheetState();
}

class _VaultRestoreSheetState extends State<_VaultRestoreSheet> {
  final _codeController = TextEditingController();
  final _pinController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    final pin = _pinController.text.trim();
    if (!SharedExpenseRecoveryCode.isWellFormed(code)) {
      setState(() {
        _error = context.l10nRead(
          'vault.recoveryCodeInvalid',
          'That recovery code doesn\'t look right.',
        );
      });
      return;
    }
    if (pin.length < _minPinLength) {
      setState(() => _error = _pinMinMessage(context));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SharedExpenseVaultService.instance
          .restore(recoveryCode: code, pin: pin);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SharedExpenseVaultWrongPinException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10nRead('vault.wrongPin', 'Wrong PIN.');
      });
    } on SharedExpenseVaultLockedException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _lockedMessage(context, error.lockedUntil);
      });
    } on SharedExpenseNoVaultException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10nRead(
          'vault.noBackupForRecoveryCode',
          'No backup found for that recovery code.',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _failureMessage(
          context,
          'vault.restoreFailed',
          'Restore failed: {error}',
          error,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: context.l10nText('Restore from another device'),
      subtitle: context.l10nText(
        'Enter the recovery code from your old device and the PIN you set there.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _codeController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.l10nText('Recovery code'),
              filled: true,
              fillColor: AppColors.cardColor(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderColor(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderColor(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primaryLight),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          _PinField(
            controller: _pinController,
            hint: context.l10nText('PIN'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) _ErrorText(_error!),
          const SizedBox(height: 16),
          _PrimaryButton(
            label: context.l10nText('Restore'),
            busy: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Change PIN sheet.
// =============================================================================

class _VaultChangePinSheet extends StatefulWidget {
  const _VaultChangePinSheet();

  @override
  State<_VaultChangePinSheet> createState() => _VaultChangePinSheetState();
}

enum _ChangePinStep { oldPin, newPin, confirmNew, success }

class _VaultChangePinSheetState extends State<_VaultChangePinSheet> {
  final _oldPinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmController = TextEditingController();

  _ChangePinStep _step = _ChangePinStep.oldPin;
  bool _busy = false;
  String? _error;
  String _oldPinBuffer = '';
  String _newPinBuffer = '';

  @override
  void dispose() {
    _oldPinController.dispose();
    _newPinController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _advanceToNewPin() {
    final pin = _oldPinController.text.trim();
    if (pin.length < _minPinLength) {
      setState(() => _error = _pinMinMessage(context));
      return;
    }
    setState(() {
      _oldPinBuffer = pin;
      _error = null;
      _step = _ChangePinStep.newPin;
    });
  }

  void _advanceToConfirm() {
    final pin = _newPinController.text.trim();
    if (pin.length < _minPinLength) {
      setState(() => _error = _pinMinMessage(context));
      return;
    }
    if (pin == _oldPinBuffer) {
      setState(() {
        _error = context.l10nRead(
          'vault.samePin',
          'Pick a new PIN, not the same one.',
        );
      });
      return;
    }
    setState(() {
      _newPinBuffer = pin;
      _error = null;
      _step = _ChangePinStep.confirmNew;
    });
  }

  Future<void> _confirmAndUpload() async {
    final confirm = _confirmController.text.trim();
    if (confirm != _newPinBuffer) {
      setState(() {
        _error = context.l10nRead(
          'vault.pinMismatch',
          'PINs don\'t match. Try again.',
        );
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SharedExpenseVaultService.instance.changePin(
        oldPin: _oldPinBuffer,
        newPin: _newPinBuffer,
      );
      if (!mounted) return;
      setState(() {
        _step = _ChangePinStep.success;
        _busy = false;
      });
    } on SharedExpenseVaultWrongPinException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.l10nRead('vault.oldPinWrong', 'Old PIN was wrong.');
        _step = _ChangePinStep.oldPin;
        _oldPinController.clear();
      });
    } on SharedExpenseVaultLockedException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _lockedMessage(context, error.lockedUntil);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _failureMessage(
          context,
          'vault.changePinFailed',
          'Couldn\'t change PIN: {error}',
          error,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _ChangePinStep.oldPin:
        return _SheetShell(
          title: context.l10nText('Change PIN'),
          subtitle: context.l10nText('Enter your current PIN to continue.'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PinField(
                controller: _oldPinController,
                hint: context.l10nText('Current PIN'),
                autofocus: true,
                onSubmitted: (_) => _advanceToNewPin(),
              ),
              if (_error != null) _ErrorText(_error!),
              const SizedBox(height: 16),
              _PrimaryButton(
                label: context.l10nText('Continue'),
                busy: _busy,
                onPressed: _advanceToNewPin,
              ),
            ],
          ),
        );
      case _ChangePinStep.newPin:
        return _SheetShell(
          title: context.l10nText('Set a new PIN'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PinField(
                controller: _newPinController,
                hint: context.l10nText('New PIN'),
                autofocus: true,
                onSubmitted: (_) => _advanceToConfirm(),
              ),
              if (_error != null) _ErrorText(_error!),
              const SizedBox(height: 16),
              _PrimaryButton(
                label: context.l10nText('Continue'),
                busy: _busy,
                onPressed: _advanceToConfirm,
              ),
            ],
          ),
        );
      case _ChangePinStep.confirmNew:
        return _SheetShell(
          title: context.l10nText('Confirm new PIN'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PinField(
                controller: _confirmController,
                hint: context.l10nText('Confirm PIN'),
                autofocus: true,
                onSubmitted: (_) => _confirmAndUpload(),
              ),
              if (_error != null) _ErrorText(_error!),
              const SizedBox(height: 16),
              _PrimaryButton(
                label: context.l10nText('Change PIN'),
                busy: _busy,
                onPressed: _confirmAndUpload,
              ),
            ],
          ),
        );
      case _ChangePinStep.success:
        return _SheetShell(
          title: context.l10nText('PIN updated'),
          subtitle: context.l10nText(
            'Your backup is now encrypted with the new PIN.',
          ),
          child: _PrimaryButton(
            label: context.l10nText('Done'),
            busy: false,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        );
    }
  }
}

// =============================================================================
// Recovery code re-display sheet.
// =============================================================================

class _VaultRecoveryCodeSheet extends StatelessWidget {
  final String code;
  const _VaultRecoveryCodeSheet({required this.code});

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: context.l10nText('Your recovery code'),
      subtitle: context.l10nText(
        'Save this somewhere safe. You need it plus your PIN to restore on a new device.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RecoveryCodeDisplay(code: code),
          const SizedBox(height: 16),
          _PrimaryButton(
            label: context.l10nText('Done'),
            busy: false,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
