part of 'shared_expenses_page.dart';

class _NudgeTarget {
  final String publicKey;
  final double amount;

  const _NudgeTarget({
    required this.publicKey,
    required this.amount,
  });
}

class _NudgePickerSheet extends StatefulWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final List<_NudgeTarget> targets;

  const _NudgePickerSheet({
    required this.group,
    required this.myPublicKey,
    required this.targets,
  });

  @override
  State<_NudgePickerSheet> createState() => _NudgePickerSheetState();
}

class _NudgePickerSheetState extends State<_NudgePickerSheet> {
  late Set<String> _selectedPks;

  @override
  void initState() {
    super.initState();
    _selectedPks = widget.targets.map((target) => target.publicKey).toSet();
  }

  List<_NudgeTarget> get _selectedTargets => widget.targets
      .where((target) => _selectedPks.contains(target.publicKey))
      .toList(growable: false);

  double get _selectedAmount => _selectedTargets.fold<double>(
        0,
        (sum, target) => sum + target.amount,
      );

  void _toggle(String publicKey) {
    setState(() {
      if (_selectedPks.contains(publicKey)) {
        _selectedPks.remove(publicKey);
      } else {
        _selectedPks.add(publicKey);
      }
    });
  }

  void _submit() {
    final selected = _selectedTargets;
    if (selected.isEmpty) return;
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    return _IosModalShell(
      title: context.l10nText('Send a nudge'),
      footer: [
        _IosFormSubmit(
          label: _selectedPks.length == 1
              ? context.l10nText('Send nudge')
              : context.l10nText('Send nudges'),
          icon: Icons.notifications_active_outlined,
          enabled: _selectedPks.isNotEmpty,
          onTap: _submit,
          topPadding: 0,
        ),
      ],
      children: [
        _IosFormGroup(
          label: context.l10nText('People who owe you'),
          labelTrailing: Text(
            _formatEtb(_selectedAmount, context),
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Column(
            children: [
              for (final target in widget.targets) ...[
                _NudgeTargetRow(
                  group: widget.group,
                  myPublicKey: widget.myPublicKey,
                  target: target,
                  selected: _selectedPks.contains(target.publicKey),
                  onTap: () => _toggle(target.publicKey),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _NudgeTargetRow extends StatelessWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final _NudgeTarget target;
  final bool selected;
  final VoidCallback onTap;

  const _NudgeTargetRow({
    required this.group,
    required this.myPublicKey,
    required this.target,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = group.displayNameFor(myPublicKey, target.publicKey);
    final color = Color(memberColorFor(group, target.publicKey));
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final borderColor = AppColors.borderColor(context);
    final cardColor = AppColors.cardColor(context);
    final initial = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryLight.withValues(alpha: 0.08)
                : cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primaryLight : borderColor,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatEtb(target.amount, context),
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                activeColor: AppColors.primaryLight,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupFormResult {
  final String groupName;
  final String displayName;
  final SharedPaymentAddress paymentAddress;

  const _GroupFormResult({
    required this.groupName,
    required this.displayName,
    required this.paymentAddress,
  });
}

class _GroupFormSheet extends StatefulWidget {
  final String title;
  final String primaryLabel;
  final String groupLabel;
  final String groupHint;
  final String nameLabel;
  final String nameHint;
  final String initialName;
  final List<AccountSummary> paymentAccounts;
  final SharedPaymentAddress initialPaymentAddress;
  /// Show a "Scan QR" affordance above the group code/name input. Used by
  /// the Join flow so the user can scan an invite QR generated on a
  /// friend's phone instead of typing the code. Defaults to false — the
  /// Create flow doesn't need it.
  final bool showQrScan;

  const _GroupFormSheet({
    required this.title,
    required this.primaryLabel,
    required this.groupLabel,
    required this.groupHint,
    required this.nameLabel,
    required this.nameHint,
    required this.initialName,
    required this.paymentAccounts,
    required this.initialPaymentAddress,
    this.showQrScan = false,
  });

  @override
  State<_GroupFormSheet> createState() => _GroupFormSheetState();
}

class _GroupFormSheetState extends State<_GroupFormSheet> {
  late final TextEditingController _groupController;
  late final TextEditingController _nameController;
  late SharedPaymentAddress _paymentAddress;
  bool _hasTriedSubmit = false;

  @override
  void initState() {
    super.initState();
    _groupController = TextEditingController();
    _nameController = TextEditingController(text: widget.initialName);
    _paymentAddress = widget.initialPaymentAddress;
  }

  @override
  void dispose() {
    _groupController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final groupName = _groupController.text.trim();
    final displayName = _nameController.text.trim();
    setState(() => _hasTriedSubmit = true);
    if (groupName.isEmpty || displayName.isEmpty) return;

    Navigator.of(context).pop(
      _GroupFormResult(
        groupName: groupName,
        displayName: displayName,
        paymentAddress: _paymentAddress,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final bottomSafeArea = mediaQuery.viewPadding.bottom;
    final keyboardLiftBuffer = keyboardInset > 0 ? 28.0 : 0.0;
    final actionBottomGap = keyboardInset > 0
        ? 4.0
        : (mediaQuery.size.height * 0.014).clamp(8.0, 14.0);
    final actionTopGap = keyboardInset > 0 ? 12.0 : 20.0;
    final formBottomPadding = keyboardInset > 0 ? 8.0 : 4.0;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset + keyboardLiftBuffer),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: mediaQuery.size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: AppColors.background(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxHeight = constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : mediaQuery.size.height * 0.9;

              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          20,
                          18,
                          20,
                          formBottomPadding,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 22),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style:
                                        theme.textTheme.headlineSmall?.copyWith(
                                      color: AppColors.textPrimary(context),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(AppIcons.close_rounded),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        AppColors.cardColor(context),
                                    foregroundColor:
                                        AppColors.textPrimary(context),
                                    minimumSize: const Size(48, 48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            if (widget.showQrScan) ...[
                              _ScanInviteChip(
                                onScanned: (code) {
                                  _groupController.text = code;
                                  setState(() {});
                                },
                              ),
                              const SizedBox(height: 14),
                            ],
                            _SheetTextField(
                              controller: _groupController,
                              label: widget.groupLabel,
                              hint: widget.groupHint,
                              textInputAction: TextInputAction.next,
                              showError: _hasTriedSubmit &&
                                  _groupController.text.trim().isEmpty,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 20),
                            _SheetTextField(
                              controller: _nameController,
                              label: widget.nameLabel,
                              hint: widget.nameHint,
                              textInputAction: TextInputAction.done,
                              showError: _hasTriedSubmit &&
                                  _nameController.text.trim().isEmpty,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _submit(),
                            ),
                            const SizedBox(height: 22),
                            _PaymentAddressSelector(
                              label: context.l10nText('PAYMENT ACCOUNT'),
                              accounts: widget.paymentAccounts,
                              selected: _paymentAddress,
                              onChanged: (address) {
                                setState(() => _paymentAddress = address);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: actionTopGap),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        bottomSafeArea + actionBottomGap,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _submit,
                          iconAlignment: IconAlignment.end,
                          icon: const Icon(
                            AppIcons.check_rounded,
                            size: 20,
                          ),
                          label: Text(widget.primaryLabel),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryLight,
                            foregroundColor: AppColors.white,
                            minimumSize: const Size(0, 58),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Inline "Scan QR" chip shown above the invite-code input on the Join
/// flow. Pushes a full-screen scanner page that returns the decoded
/// payload — typically the bare UUID we ship in the share text — and
/// hands it back via [onScanned].
class _ScanInviteChip extends StatelessWidget {
  final ValueChanged<String> onScanned;
  const _ScanInviteChip({required this.onScanned});

  Future<void> _open(BuildContext context) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => const _ScanInvitePage(),
      ),
    );
    if (code == null || code.isEmpty) return;
    onScanned(code);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primaryLight.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primaryLight.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              AppIcons.qr_code_scanner_rounded,
              size: 22,
              color: AppColors.primaryLight,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10nText('Scan invite QR'),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10nText(
                      'Point the camera at your friend\'s invite code.',
                    ),
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              AppIcons.chevron_right,
              size: 18,
              color: AppColors.textTertiary(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanInvitePage extends StatefulWidget {
  const _ScanInvitePage();

  @override
  State<_ScanInvitePage> createState() => _ScanInvitePageState();
}

class _ScanInvitePageState extends State<_ScanInvitePage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final code in capture.barcodes) {
      final value = code.rawValue;
      if (value == null || value.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(value.trim());
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: Text(context.l10nText('Scan invite QR')),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    context.l10nText(
                      'Camera unavailable. Enable camera permission and try again.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            },
          ),
          // Lightweight viewfinder frame in the centre to hint where to aim.
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.white.withValues(alpha: 0.75),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                context.l10nText(
                  'Line up your friend\'s invite QR inside the frame.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputAction textInputAction;
  final bool showError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  const _SheetTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.textInputAction,
    required this.showError,
    required this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor =
        showError ? AppColors.red : AppColors.borderColor(context);
    final focusedBorderColor =
        showError ? AppColors.red : AppColors.primaryLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.trim().isNotEmpty) ...[
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.textSecondary(context),
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: controller,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          style: theme.textTheme.titleMedium?.copyWith(
            color: AppColors.textPrimary(context),
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.textTertiary(context),
              fontWeight: FontWeight.w400,
            ),
            filled: true,
            fillColor: AppColors.cardColor(context),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: focusedBorderColor,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.red,
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.red,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentAddressSelector extends StatelessWidget {
  final String label;
  final List<AccountSummary> accounts;
  final SharedPaymentAddress selected;
  final ValueChanged<SharedPaymentAddress> onChanged;

  const _PaymentAddressSelector({
    required this.label,
    required this.accounts,
    required this.selected,
    required this.onChanged,
  });

  SharedPaymentAddress _addressFor(AccountSummary account) {
    return SharedPaymentAddress(
      bankId: account.bankId,
      accountNumber: account.accountNumber,
      accountHolderName: account.accountHolderName,
    );
  }

  bool _isSelected(AccountSummary account) {
    return account.bankId == selected.bankId &&
        account.accountNumber == selected.accountNumber;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: accounts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final account = accounts[index];
              final address = _addressFor(account);
              return _PaymentAddressChip(
                bank: _sharedExpenseBankFor(account.bankId),
                title: _sharedPaymentBankLabel(context, account.bankId),
                selected: _isSelected(account),
                onTap: () => onChanged(address),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PaymentAddressChip extends StatelessWidget {
  final Bank bank;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentAddressChip({
    required this.bank,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor =
        selected ? AppColors.primaryLight : AppColors.borderColor(context);
    final textColor =
        selected ? AppColors.primaryLight : AppColors.textSecondary(context);

    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 82,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 54,
                height: 54,
                padding: EdgeInsets.all(selected ? 3 : 4),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryLight.withValues(alpha: 0.08)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: borderColor,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: ClipOval(
                  child: bank.image.isEmpty
                      ? _PaymentBankFallback()
                      : Image.asset(
                          bank.image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _PaymentBankFallback(),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: textColor,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Add-expense sheet (minimal — amount + reason, equal split among all members).
// ============================================================================

abstract class _ExpenseSheetResult {
  const _ExpenseSheetResult();
}

class _ExpenseSheetSave extends _ExpenseSheetResult {
  final double amount;
  final String reason;
  final String paidBy;
  final List<String> splitAmong;
  final int timestamp;
  final String? linkedTxRef;
  const _ExpenseSheetSave({
    required this.amount,
    required this.reason,
    required this.paidBy,
    required this.splitAmong,
    required this.timestamp,
    this.linkedTxRef,
  });
}

class _ExpenseSheetDelete extends _ExpenseSheetResult {
  const _ExpenseSheetDelete();
}

typedef _ExpenseSheetSubmit = Future<bool> Function(
  _ExpenseSheetResult result,
);

class _ExpenseDraftSheet extends StatefulWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final SharedExpense? editing;
  final double? initialAmount;
  final String? initialReason;
  final String? initialLinkedTxRef;
  final String? submittingLabel;
  final _ExpenseSheetSubmit? onSubmit;

  const _ExpenseDraftSheet({
    required this.group,
    required this.myPublicKey,
    this.editing,
    this.initialAmount,
    this.initialReason,
    this.initialLinkedTxRef,
    this.submittingLabel,
    this.onSubmit,
  });

  @override
  State<_ExpenseDraftSheet> createState() => _ExpenseDraftSheetState();
}

class _ExpenseDraftSheetState extends State<_ExpenseDraftSheet> {
  late final TextEditingController _amountCtrl = TextEditingController(
    text: _formatExpenseAmountInput(
      widget.editing?.amount ?? widget.initialAmount,
    ),
  );
  late final TextEditingController _reasonCtrl = TextEditingController(
    text: widget.editing?.reason ?? widget.initialReason ?? '',
  );
  late final FocusNode _amountFocusNode = FocusNode();
  late final FocusNode _reasonFocusNode = FocusNode();
  late String _paidBy = widget.editing?.paidBy ?? widget.myPublicKey;
  late Set<String> _split = widget.editing != null
      ? widget.editing!.splitAmong.toSet()
      : _memberKeysForGroup(widget.group);
  late DateTime _paidAt = DateTime.fromMillisecondsSinceEpoch(
    widget.editing?.timestamp ?? DateTime.now().millisecondsSinceEpoch,
  );
  late String? _linkedTxRef =
      widget.editing?.linkedTxRef ?? widget.initialLinkedTxRef;
  bool _deleteArmed = false;
  bool _isSubmitting = false;
  String? _submittingLabel;
  Timer? _deleteDisarmTimer;

  bool get _isEditing => widget.editing != null;
  bool get _startsFromLinkedTransaction =>
      widget.editing == null && widget.initialLinkedTxRef != null;
  bool get _requiresLinkedTransaction =>
      widget.editing == null && widget.initialLinkedTxRef != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_startsFromLinkedTransaction) {
        _focusReasonField(selectAll: true);
      } else {
        _amountFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    _amountFocusNode.dispose();
    _reasonFocusNode.dispose();
    _deleteDisarmTimer?.cancel();
    super.dispose();
  }

  void _focusReasonField({bool selectAll = false}) {
    _reasonFocusNode.requestFocus();
    final text = _reasonCtrl.text;
    _reasonCtrl.selection = selectAll
        ? TextSelection(baseOffset: 0, extentOffset: text.length)
        : TextSelection.collapsed(offset: text.length);
  }

  Future<void> _submitResult(
    _ExpenseSheetResult result, {
    required String submittingLabel,
  }) async {
    if (_isSubmitting) return;
    final submit = widget.onSubmit;
    if (submit == null) {
      Navigator.of(context).pop(result);
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isSubmitting = true;
      _submittingLabel = submittingLabel;
    });

    var shouldClose = false;
    try {
      shouldClose = await submit(result);
    } catch (_) {
      shouldClose = false;
    }
    if (!mounted) return;
    if (shouldClose) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      _isSubmitting = false;
      _submittingLabel = null;
    });
  }

  void _submit() {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final reason = _reasonCtrl.text.trim();
    if (_isSubmitting || amount <= 0 || reason.isEmpty || _split.isEmpty) {
      return;
    }
    unawaited(
      _submitResult(
        _ExpenseSheetSave(
          amount: amount,
          reason: reason,
          paidBy: _paidBy,
          splitAmong: _split.toList(),
          timestamp: _paidAt.millisecondsSinceEpoch,
          linkedTxRef: _linkedTxRef,
        ),
        submittingLabel:
            widget.submittingLabel ?? (_isEditing ? 'Saving' : 'Adding'),
      ),
    );
  }

  Future<void> _pickPaidAt() async {
    final now = DateTime.now();
    // Expenses can't be in the future — you can't have paid for something
    // tomorrow. Cap the picker to today.
    final initial = _paidAt.isAfter(now) ? now : _paidAt;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (selected == null || !mounted) return;
    setState(() {
      _paidAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _paidAt.hour,
        _paidAt.minute,
      );
    });
  }

  Transaction? _linkedTransaction(TransactionProvider provider) {
    return provider.transactionByReference(_linkedTxRef);
  }

  Future<void> _pickLinkedTransaction() async {
    final provider = context.read<TransactionProvider>();
    final currentRef = _linkedTxRef;
    final linkedRefs = provider.sharedExpenseLinkedRefs
        .where((ref) => ref != currentRef)
        .toSet();
    final candidates = provider.allTransactions
        .where((transaction) =>
            transaction.reference.trim().isNotEmpty &&
            !linkedRefs.contains(transaction.reference))
        .toList(growable: false)
      ..sort((a, b) {
        final aTime = _timestampFromTransaction(a) ?? 0;
        final bTime = _timestampFromTransaction(b) ?? 0;
        return bTime.compareTo(aTime);
      });

    final selected = await showModalBottomSheet<Transaction>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.black.withValues(alpha: 0.5),
      builder: (_) => _LinkedTransactionPickerSheet(
        transactions: candidates,
        selectedRef: currentRef,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _linkedTxRef = selected.reference;
      final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
      if (amount <= 0) {
        _amountCtrl.text = _formatExpenseAmountInput(selected.amount.abs());
      }
      if (_reasonCtrl.text.trim().isEmpty) {
        _reasonCtrl.text = _splitReasonForTransaction(selected);
      }
    });
    _focusReasonField();
  }

  void _clearLinkedTransaction() {
    if (_requiresLinkedTransaction) return;
    setState(() => _linkedTxRef = null);
  }

  void _onDeleteTap() {
    if (_isSubmitting) return;
    if (!_deleteArmed) {
      setState(() => _deleteArmed = true);
      _deleteDisarmTimer?.cancel();
      _deleteDisarmTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _deleteArmed = false);
      });
      return;
    }
    unawaited(
      _submitResult(
        const _ExpenseSheetDelete(),
        submittingLabel: 'Deleting',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final transactionProvider = context.watch<TransactionProvider>();
    final linkedTransaction = _linkedTransaction(transactionProvider);
    // Me first, then everyone else alphabetical by resolved display name
    // (case-insensitive). Same ordering used in the members tab so the
    // expense sheet feels consistent.
    String orderKey(String pk) {
      final name = widget.group
          .displayNameFor(widget.myPublicKey, pk)
          .trim();
      return (name.isNotEmpty ? name : pk).toLowerCase();
    }

    final keys = widget.group.members
        .map((m) => m.devicePublicKey)
        .where((k) => k.isNotEmpty)
        .toList()
      ..sort((a, b) {
        if (a == widget.myPublicKey) return -1;
        if (b == widget.myPublicKey) return 1;
        return orderKey(a).compareTo(orderKey(b));
      });

    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final reason = _reasonCtrl.text.trim();
    final canSave = amount > 0 && reason.isNotEmpty && _split.isNotEmpty;
    final allSelected = keys.isNotEmpty && _split.length == keys.length;

    return PopScope(
      canPop: !_isSubmitting,
      child: _IosModalShell(
        title: _isEditing ? 'Edit Expense' : 'Add Expense',
        closeEnabled: !_isSubmitting,
        footer: [
          _IosFormSubmit(
            label: _isSubmitting
                ? (_submittingLabel ??
                    (widget.submittingLabel ??
                        (_isEditing ? 'Saving' : 'Adding')))
                : _isEditing
                    ? 'Save'
                    : 'Add',
            enabled: canSave && !_isSubmitting,
            isBusy: _isSubmitting,
            onTap: _submit,
            topPadding: 0,
          ),
          if (_isEditing) ...[
            const SizedBox(height: 10),
            _IosDangerButton(
              label: _deleteArmed ? 'Tap again to delete' : 'Delete expense',
              icon: Icons.delete_outline,
              armed: _deleteArmed,
              onTap: _isSubmitting ? null : _onDeleteTap,
            ),
          ],
        ],
        children: [
          // Amount row — centered huge input with currency suffix + bottom rule.
          _IosAmountRow(
            controller: _amountCtrl,
            focusNode: _amountFocusNode,
            autofocus: !_startsFromLinkedTransaction,
            onChanged: (_) => setState(() {}),
          ),
          _IosFormGroup(
            label: 'For what?',
            child: _IosFormInput(
              controller: _reasonCtrl,
              focusNode: _reasonFocusNode,
              autofocus: _startsFromLinkedTransaction,
              hint: 'e.g., Dinner, Hotel, Taxi',
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
          ),
          _IosFormGroup(
            label: 'When',
            child: _IosValueRow(
              icon: AppIcons.calendar_today_outlined,
              title: _formatSharedDate(_paidAt),
              onTap: _pickPaidAt,
            ),
          ),
          _IosFormGroup(
            label: 'Transaction',
            labelTrailing: _linkedTxRef == null || _requiresLinkedTransaction
                ? null
                : _IosTextAction(
                    label: 'Remove',
                    onTap: _clearLinkedTransaction,
                  ),
            child: _IosValueRow(
              icon: AppIcons.receipt_long_rounded,
              title: linkedTransaction == null
                  ? _linkedTxRef == null
                      ? context.l10nText('Link transaction')
                      : context.l10nText('Linked transaction')
                  : _transactionCounterpartyLabel(linkedTransaction),
              subtitle: linkedTransaction == null
                  ? _linkedTxRef ?? context.l10nText('Optional')
                  : _transactionLinkSummary(linkedTransaction, context),
              onTap: _pickLinkedTransaction,
            ),
          ),
          _IosFormGroup(
            label: 'Paid by',
            child: _IosSharedMemberSelector(
              group: widget.group,
              myPublicKey: widget.myPublicKey,
              memberKeys: keys,
              isSelected: (pk) => _paidBy == pk,
              onTap: (pk) => setState(() => _paidBy = pk),
            ),
          ),
          _IosFormGroup(
            label: 'Split between',
            labelTrailing: _IosTextAction(
              label: allSelected ? 'None' : 'All',
              onTap: () => setState(() {
                _split = allSelected ? <String>{} : keys.toSet();
              }),
            ),
            child: _IosSharedMemberSelector(
              group: widget.group,
              myPublicKey: widget.myPublicKey,
              memberKeys: keys,
              isSelected: _split.contains,
              onTap: (pk) => setState(() {
                if (_split.contains(pk)) {
                  _split = {..._split}..remove(pk);
                } else {
                  _split = {..._split, pk};
                }
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedTransactionPickerSheet extends StatefulWidget {
  final List<Transaction> transactions;
  final String? selectedRef;

  const _LinkedTransactionPickerSheet({
    required this.transactions,
    required this.selectedRef,
  });

  @override
  State<_LinkedTransactionPickerSheet> createState() =>
      _LinkedTransactionPickerSheetState();
}

class _LinkedTransactionPickerSheetState
    extends State<_LinkedTransactionPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Transaction> _filteredTransactions() {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.transactions
        : widget.transactions.where((transaction) {
            return transaction.reference.toLowerCase().contains(query) ||
                _transactionCounterpartyLabel(transaction)
                    .toLowerCase()
                    .contains(query) ||
                (transaction.note?.toLowerCase().contains(query) ?? false);
          }).toList(growable: false);
    return filtered.take(80).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredTransactions();
    return _IosModalShell(
      title: 'Link Transaction',
      children: [
        _IosSearchField(
          controller: _searchCtrl,
          hint: 'Search transactions',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Text(
              context.l10nText('No available transactions'),
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          for (final transaction in filtered) ...[
            _LinkedTransactionOption(
              transaction: transaction,
              selected: transaction.reference == widget.selectedRef,
              onTap: () => Navigator.of(context).pop(transaction),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _LinkedTransactionOption extends StatelessWidget {
  final Transaction transaction;
  final bool selected;
  final VoidCallback onTap;

  const _LinkedTransactionOption({
    required this.transaction,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimary(context);
    final textSecondary = AppColors.textSecondary(context);
    final cardColor = AppColors.cardColor(context);
    final borderColor =
        selected ? AppColors.primaryLight : AppColors.borderColor(context);
    final date = _transactionDateLabel(transaction);
    final subtitle = [
      _formatEtb(transaction.amount.abs(), context),
      if (date.isNotEmpty) date,
      _logId(transaction.reference),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                AppIcons.receipt_long_rounded,
                color: AppColors.primaryLight,
                size: 17,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _transactionCounterpartyLabel(transaction),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                AppIcons.check_circle_rounded,
                color: AppColors.primaryLight,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Invite sheet — QR code + OS share sheet + copy fallback. Opened from the
// kebab menu on synced cards and from the Copy invite pill on pending cards
// (so the user gets the same flow whether they're inviting more people to a
// group they're already in, or sharing the code they themselves used while
// pending).
// ============================================================================

Future<void> showGroupInviteSheet(
  BuildContext context, {
  required String groupName,
  required String inviteCode,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.black.withValues(alpha: 0.5),
    builder: (sheetContext) => _GroupInviteSheet(
      groupName: groupName,
      inviteCode: inviteCode,
    ),
  );
}

class _GroupInviteSheet extends StatelessWidget {
  final String groupName;
  final String inviteCode;
  const _GroupInviteSheet({
    required this.groupName,
    required this.inviteCode,
  });

  String _shareText(BuildContext context) {
    // l10nText uses context.watch under the hood; this method is called
    // from the Share button's onTap (outside a build pass), so we must
    // use the read-only variant or Provider asserts.
    final groupLabel = groupName.trim().isEmpty ? 'a Totals group' : groupName;
    return context
        .l10nTextRead('Join "{group}" on Totals with this invite code:\n{code}')
        .replaceFirst('{group}', groupLabel)
        .replaceFirst('{code}', inviteCode);
  }

  @override
  Widget build(BuildContext context) {
    final shellTitle = groupName.trim().isEmpty
        ? context.l10nText('Invite to group')
        : context
            .l10n('shared.inviteTo', 'Invite to {name}')
            .replaceFirst('{name}', groupName);
    return _IosModalShell(
      title: shellTitle,
      footer: [
        _IosFormSubmit(
          label: context.l10nText('Share'),
          icon: AppIcons.share_outline,
          enabled: true,
          onTap: () async {
            debugPrint('debug: invite-share button tapped');
            final messenger = ScaffoldMessenger.maybeOf(context);
            final unavailableText = context
                .l10nTextRead('Sharing is unavailable on this device.');
            final box = context.findRenderObject() as RenderBox?;
            final shareText = _shareText(context);
            debugPrint(
              'debug: invite-share text="${shareText.replaceAll('\n', ' / ')}"',
            );
            try {
              // iPad / desktop need a popover anchor or Share.share()
              // silently no-ops. On phone Android/iOS this is harmless.
              final result = await Share.share(
                shareText,
                subject: shellTitle,
                sharePositionOrigin: box == null
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size,
              );
              debugPrint(
                'debug: invite-share result=${result.status} raw=${result.raw}',
              );
              if (result.status == ShareResultStatus.unavailable) {
                messenger?.showSnackBar(
                  SnackBar(
                    content: Text(unavailableText),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              if (context.mounted) Navigator.of(context).pop();
            } catch (error, stack) {
              debugPrint('debug: invite-share threw: $error\n$stack');
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(error.toString()),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          topPadding: 0,
        ),
        const SizedBox(height: 10),
        _IosSecondaryButton(
          label: context.l10nText('Copy code'),
          icon: Icons.content_copy,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: inviteCode));
            if (!context.mounted) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            Navigator.of(context).pop();
            messenger?.showSnackBar(
              SnackBar(
                content: Text(context.l10nTextRead('Invite code copied')),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
      ],
      children: [
        // White card around the QR so it scans cleanly on a dark theme too.
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: SizedBox(
              width: 220,
              height: 220,
              child: PrettyQrView.data(
                data: inviteCode,
                decoration: const PrettyQrDecoration(
                  shape: PrettyQrSmoothSymbol(
                    color: AppColors.black,
                    roundFactor: 0.65,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          context.l10nText(
            'Friends can scan this QR or use the code below.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceColor(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderColor(context)),
          ),
          child: Text(
            inviteCode,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontFeatures: const [FontFeature.tabularFigures()],
              color: AppColors.textPrimary(context),
              fontSize: 13.5,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Group settings sheet — edit name + your display name, copy invite, leave.
// ============================================================================

abstract class _GroupSettingsResult {
  const _GroupSettingsResult();
}

class _GroupSettingsSave extends _GroupSettingsResult {
  final String name;
  final String displayName;
  final bool backfillNewMembers;
  final SharedPaymentAddress paymentAddress;
  const _GroupSettingsSave(
    this.name,
    this.displayName,
    this.backfillNewMembers,
    this.paymentAddress,
  );
}

class _GroupSettingsCopyInvite extends _GroupSettingsResult {
  const _GroupSettingsCopyInvite();
}

class _GroupSettingsLeave extends _GroupSettingsResult {
  const _GroupSettingsLeave();
}

class _GroupSettingsSheet extends StatefulWidget {
  final String initialName;
  final String initialDisplayName;
  final bool initialBackfillNewMembers;
  final List<AccountSummary> paymentAccounts;
  final SharedPaymentAddress initialPaymentAddress;
  const _GroupSettingsSheet({
    required this.initialName,
    required this.initialDisplayName,
    required this.initialBackfillNewMembers,
    required this.paymentAccounts,
    required this.initialPaymentAddress,
  });

  @override
  State<_GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

class _GroupSettingsSheetState extends State<_GroupSettingsSheet> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _displayCtrl =
      TextEditingController(text: widget.initialDisplayName);
  late bool _backfillNewMembers = widget.initialBackfillNewMembers;
  late SharedPaymentAddress _paymentAddress = widget.initialPaymentAddress;
  bool _leaveArmed = false;
  Timer? _disarmTimer;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _displayCtrl.dispose();
    _disarmTimer?.cancel();
    super.dispose();
  }

  void _onLeaveTap() {
    if (!_leaveArmed) {
      setState(() => _leaveArmed = true);
      _disarmTimer?.cancel();
      _disarmTimer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _leaveArmed = false);
      });
      return;
    }
    Navigator.of(context).pop(const _GroupSettingsLeave());
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _nameCtrl.text.trim().isNotEmpty &&
        _displayCtrl.text.trim().isNotEmpty &&
        (_nameCtrl.text.trim() != widget.initialName ||
            _displayCtrl.text.trim() != widget.initialDisplayName ||
            _backfillNewMembers != widget.initialBackfillNewMembers ||
            _paymentAddress != widget.initialPaymentAddress);

    return _IosModalShell(
      title: 'Edit Group',
      footer: [
        _IosFormSubmit(
          label: 'Save',
          enabled: canSave,
          onTap: () => Navigator.of(context).pop(
            _GroupSettingsSave(
              _nameCtrl.text.trim(),
              _displayCtrl.text.trim(),
              _backfillNewMembers,
              _paymentAddress,
            ),
          ),
          topPadding: 0,
        ),
        const SizedBox(height: 10),
        _IosSecondaryButton(
          label: 'Copy invite',
          icon: Icons.content_copy,
          onTap: () =>
              Navigator.of(context).pop(const _GroupSettingsCopyInvite()),
        ),
        const SizedBox(height: 10),
        _IosDangerButton(
          label: _leaveArmed ? 'Tap again to confirm' : 'Leave group',
          icon: Icons.logout,
          armed: _leaveArmed,
          onTap: _onLeaveTap,
        ),
      ],
      children: [
        _IosFormGroup(
          label: 'Group name',
          child: _IosFormInput(
            controller: _nameCtrl,
            hint: 'Trip to Lalibela, Roommates…',
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
        ),
        _IosFormGroup(
          label: 'Your name',
          child: _IosFormInput(
            controller: _displayCtrl,
            hint: 'How other members see you',
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
          ),
        ),
        _IosFormGroup(
          label: 'New members',
          child: _IosCheckboxRow(
            title: 'Backfill history',
            value: _backfillNewMembers,
            onChanged: (value) => setState(() {
              _backfillNewMembers = value;
            }),
          ),
        ),
        _IosFormGroup(
          label: 'Payment account',
          child: _PaymentAddressSelector(
            label: '',
            accounts: widget.paymentAccounts,
            selected: _paymentAddress,
            onChanged: (address) {
              setState(() => _paymentAddress = address);
            },
          ),
        ),
      ],
    );
  }
}

