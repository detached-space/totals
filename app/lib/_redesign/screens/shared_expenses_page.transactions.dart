part of 'shared_expenses_page.dart';


class _SharedTransactionFilter {
  final String? kind;
  final String? paidBy;
  final double? minAmount;
  final double? maxAmount;
  final DateTime? startDate;
  final DateTime? endDate;

  const _SharedTransactionFilter({
    this.kind,
    this.paidBy,
    this.minAmount,
    this.maxAmount,
    this.startDate,
    this.endDate,
  });

  bool get isActive =>
      kind != null ||
      paidBy != null ||
      minAmount != null ||
      maxAmount != null ||
      startDate != null ||
      endDate != null;

  int get activeCount {
    int count = 0;
    if (kind != null) count++;
    if (paidBy != null) count++;
    if (minAmount != null || maxAmount != null) count++;
    if (startDate != null || endDate != null) count++;
    return count;
  }
}

class _SharedTransactionPayerOption {
  final String publicKey;
  final String label;

  const _SharedTransactionPayerOption({
    required this.publicKey,
    required this.label,
  });
}

class _SharedGroupTransactionsView extends StatefulWidget {
  final SharedExpenseGroup group;
  final String myPublicKey;
  final VoidCallback onBack;
  final ValueChanged<SharedExpense> onEditExpense;

  const _SharedGroupTransactionsView({
    required this.group,
    required this.myPublicKey,
    required this.onBack,
    required this.onEditExpense,
  });

  @override
  State<_SharedGroupTransactionsView> createState() =>
      _SharedGroupTransactionsViewState();
}

class _SharedGroupTransactionsViewState
    extends State<_SharedGroupTransactionsView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  _SharedTransactionFilter _filter = const _SharedTransactionFilter();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilterSheet() async {
    final payerOptions = _payerOptions();
    final result = await showModalBottomSheet<_SharedTransactionFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SharedTransactionsFilterSheet(
        currentFilter: _filter,
        payerOptions: payerOptions,
      ),
    );

    if (!mounted || result == null) return;
    setState(() => _filter = result);
  }

  List<_SharedTransactionPayerOption> _payerOptions() {
    final keys = <String>{};
    for (final member in widget.group.members) {
      if (member.devicePublicKey.isNotEmpty) {
        keys.add(member.devicePublicKey);
      }
    }
    for (final expense in widget.group.expenses) {
      if (expense.paidBy.isNotEmpty) keys.add(expense.paidBy);
    }

    final options = keys.map((publicKey) {
      final label = widget.group.displayNameFor(widget.myPublicKey, publicKey);
      return _SharedTransactionPayerOption(
        publicKey: publicKey,
        label: label.trim().isEmpty ? _logId(publicKey) : label,
      );
    }).toList()
      ..sort((a, b) {
        if (a.publicKey == widget.myPublicKey) return -1;
        if (b.publicKey == widget.myPublicKey) return 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return options;
  }

  List<SharedExpense> _filteredExpenses() {
    final queryLower = _query.trim().toLowerCase();
    final result = widget.group.expenses.where((expense) {
      if (expense.deleted) return false;

      if (_filter.kind != null && expense.kind != _filter.kind) {
        return false;
      }

      if (_filter.paidBy != null && expense.paidBy != _filter.paidBy) {
        return false;
      }

      if (_filter.minAmount != null && expense.amount < _filter.minAmount!) {
        return false;
      }

      if (_filter.maxAmount != null && expense.amount > _filter.maxAmount!) {
        return false;
      }

      if (_filter.startDate != null || _filter.endDate != null) {
        if (expense.timestamp <= 0) return false;
        final timestamp =
            DateTime.fromMillisecondsSinceEpoch(expense.timestamp);
        if (_filter.startDate != null) {
          final start = DateTime(
            _filter.startDate!.year,
            _filter.startDate!.month,
            _filter.startDate!.day,
          );
          if (timestamp.isBefore(start)) return false;
        }
        if (_filter.endDate != null) {
          final end = _filter.endDate!
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1));
          if (timestamp.isAfter(end)) return false;
        }
      }

      if (queryLower.isEmpty) return true;
      final reasonMatch = expense.reason.toLowerCase().contains(queryLower);
      final payerName = widget.group
          .displayNameFor(widget.myPublicKey, expense.paidBy)
          .toLowerCase();
      final payerMatch = payerName.contains(queryLower);
      final recipientMatch = expense.splitAmong.any((publicKey) {
        final label = widget.group
            .displayNameFor(widget.myPublicKey, publicKey)
            .toLowerCase();
        return label.contains(queryLower);
      });
      return reasonMatch || payerMatch || recipientMatch;
    }).toList(growable: false)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.trim().isNotEmpty;
    final hasEmptyFilterState = hasQuery || _filter.isActive;
    final filtered = _filteredExpenses();
    final transactionCount = filtered.length;

    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SharedTransactionsTopBar(
                      groupName: widget.group.name,
                      onBack: widget.onBack,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      context.l10nText('Transactions'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: AppColors.textPrimary(context),
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                    ),
                    const SizedBox(height: 18),
                    _SharedTransactionsSearchFilterRow(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      onFilterTap: _openFilterSheet,
                      activeFilterCount: _filter.activeCount,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 128),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SharedTransactionsCountHeader(count: transactionCount),
                    if (filtered.isEmpty)
                      _SharedTransactionsEmptyState(
                          hasQuery: hasEmptyFilterState)
                    else
                      Column(
                        children: [
                          for (var i = 0; i < filtered.length; i++)
                            _SharedExpenseRow(
                              expense: filtered[i],
                              group: widget.group,
                              myPublicKey: widget.myPublicKey,
                              showDivider: i < filtered.length - 1,
                              onTap: () => widget.onEditExpense(filtered[i]),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedTransactionsTopBar extends StatelessWidget {
  final String groupName;
  final VoidCallback onBack;

  const _SharedTransactionsTopBar({
    required this.groupName,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onBack,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              AppIcons.chevron_left,
              size: 20,
              color: AppColors.textTertiary(context),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                groupName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.textTertiary(context),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SharedTransactionsSearchFilterRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onFilterTap;
  final int activeFilterCount;

  const _SharedTransactionsSearchFilterRow({
    required this.controller,
    required this.onChanged,
    required this.onFilterTap,
    this.activeFilterCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary(context),
              ),
              decoration: InputDecoration(
                hintText: context.l10nText('Search reason or member...'),
                hintStyle: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                filled: true,
                fillColor: AppColors.surfaceColor(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderColor(context)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.borderColor(context)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.primaryLight,
                    width: 1.3,
                  ),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _SharedTransactionsFilterActionButton(
          onTap: onFilterTap,
          activeFilterCount: activeFilterCount,
        ),
      ],
    );
  }
}

class _SharedTransactionsFilterActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final int activeFilterCount;

  const _SharedTransactionsFilterActionButton({
    required this.onTap,
    this.activeFilterCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    const size = 44.0;
    const badgeSize = 18.0;
    const badgeOffset = -4.0;
    const iconSize = 22.0;
    const borderRadius = 10.0;
    const badgeFontSize = 10.0;
    final hasFilters = activeFilterCount > 0;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: hasFilters
                  ? AppColors.primaryDark.withValues(alpha: 0.1)
                  : AppColors.cardColor(context),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: hasFilters
                    ? AppColors.primaryDark
                    : AppColors.borderColor(context),
              ),
            ),
            child: Icon(
              AppIcons.filter_list,
              color: hasFilters
                  ? AppColors.primaryDark
                  : AppColors.textSecondary(context),
              size: iconSize,
            ),
          ),
          if (hasFilters)
            Positioned(
              top: badgeOffset,
              right: badgeOffset,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$activeFilterCount',
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: badgeFontSize,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SharedTransactionsFilterSheet extends StatefulWidget {
  final _SharedTransactionFilter currentFilter;
  final List<_SharedTransactionPayerOption> payerOptions;

  const _SharedTransactionsFilterSheet({
    required this.currentFilter,
    required this.payerOptions,
  });

  @override
  State<_SharedTransactionsFilterSheet> createState() =>
      _SharedTransactionsFilterSheetState();
}

class _SharedTransactionsFilterSheetState
    extends State<_SharedTransactionsFilterSheet> {
  late String? _selectedKind;
  late String? _selectedPaidBy;
  late final TextEditingController _minAmountController;
  late final TextEditingController _maxAmountController;
  String? _amountErrorText;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _selectedKind = widget.currentFilter.kind;
    _selectedPaidBy = widget.currentFilter.paidBy;
    _minAmountController = TextEditingController(
      text: _formatAmountInput(widget.currentFilter.minAmount),
    );
    _maxAmountController = TextEditingController(
      text: _formatAmountInput(widget.currentFilter.maxAmount),
    );
    _startDate = widget.currentFilter.startDate;
    _endDate = widget.currentFilter.endDate;
  }

  @override
  void dispose() {
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  void _clearAll() {
    setState(() {
      _selectedKind = null;
      _selectedPaidBy = null;
      _minAmountController.clear();
      _maxAmountController.clear();
      _amountErrorText = null;
      _startDate = null;
      _endDate = null;
    });
  }

  void _apply() {
    final minRaw = _minAmountController.text;
    final maxRaw = _maxAmountController.text;
    final minAmount = _parseAmountInput(minRaw);
    final maxAmount = _parseAmountInput(maxRaw);
    final amountError = _buildAmountValidationMessage(
      minRaw: minRaw,
      maxRaw: maxRaw,
      minAmount: minAmount,
      maxAmount: maxAmount,
    );

    if (amountError != null) {
      setState(() => _amountErrorText = amountError);
      return;
    }

    Navigator.of(context).pop(
      _SharedTransactionFilter(
        kind: _selectedKind,
        paidBy: _selectedPaidBy,
        minAmount: minAmount,
        maxAmount: maxAmount,
        startDate: _startDate,
        endDate: _endDate,
      ),
    );
  }

  double? _parseAmountInput(String raw) {
    final normalized = raw.replaceAll(',', '').trim();
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  bool _hasInvalidAmountInput(String raw) {
    final normalized = raw.replaceAll(',', '').trim();
    return normalized.isNotEmpty && double.tryParse(normalized) == null;
  }

  String? _buildAmountValidationMessage({
    required String minRaw,
    required String maxRaw,
    required double? minAmount,
    required double? maxAmount,
  }) {
    if (_hasInvalidAmountInput(minRaw) || _hasInvalidAmountInput(maxRaw)) {
      return 'Enter a valid amount';
    }
    if (minAmount != null && maxAmount != null && maxAmount < minAmount) {
      return 'Maximum must be at least minimum.';
    }
    return null;
  }

  String _formatAmountInput(double? amount) {
    if (amount == null) return '';
    if (amount == amount.roundToDouble()) {
      return amount.toStringAsFixed(0);
    }
    return amount
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _handleAmountChanged(String _) {
    if (_amountErrorText == null) return;
    final minRaw = _minAmountController.text;
    final maxRaw = _maxAmountController.text;
    final minAmount = _parseAmountInput(minRaw);
    final maxAmount = _parseAmountInput(maxRaw);
    setState(() {
      _amountErrorText = _buildAmountValidationMessage(
        minRaw: minRaw,
        maxRaw: maxRaw,
        minAmount: minAmount,
        maxAmount: maxAmount,
      );
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = (isStart ? _startDate : _endDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) {
        final dark = AppColors.isDark(ctx);
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: dark
                ? const ColorScheme.dark(
                    primary: AppColors.primaryLight,
                    onPrimary: AppColors.white,
                    surface: AppColors.darkCard,
                    onSurface: AppColors.white,
                  )
                : const ColorScheme.light(
                    primary: AppColors.primaryDark,
                    onPrimary: AppColors.white,
                    surface: AppColors.white,
                    onSurface: AppColors.slate900,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final navBarPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.slate400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10nText('Filter Transactions'),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    AppIcons.close,
                    color: AppColors.textSecondary(context),
                  ),
                  splashRadius: 20,
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                16 + bottomPadding + navBarPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('TYPE'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SharedFilterSheetChip(
                        label: 'All',
                        selected: _selectedKind == null,
                        onTap: () => setState(() => _selectedKind = null),
                      ),
                      _SharedFilterSheetChip(
                        label: 'Expense',
                        selected: _selectedKind == 'expense',
                        onTap: () => setState(() => _selectedKind = 'expense'),
                      ),
                      _SharedFilterSheetChip(
                        label: 'Settlement',
                        selected: _selectedKind == 'settlement',
                        onTap: () =>
                            setState(() => _selectedKind = 'settlement'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('PAID BY'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SharedFilterSheetChip(
                        label: 'All',
                        selected: _selectedPaidBy == null,
                        onTap: () => setState(() => _selectedPaidBy = null),
                      ),
                      for (final payer in widget.payerOptions)
                        _SharedFilterSheetChip(
                          label: payer.label,
                          selected: _selectedPaidBy == payer.publicKey,
                          onTap: () =>
                              setState(() => _selectedPaidBy = payer.publicKey),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('AMOUNT RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SharedAmountFilterField(
                          controller: _minAmountController,
                          hint: 'Min',
                          hasError: _amountErrorText != null,
                          onChanged: _handleAmountChanged,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SharedAmountFilterField(
                          controller: _maxAmountController,
                          hint: 'Max',
                          hasError: _amountErrorText != null,
                          onChanged: _handleAmountChanged,
                        ),
                      ),
                    ],
                  ),
                  if (_amountErrorText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      context.l10nText(_amountErrorText!),
                      style: const TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel('DATE RANGE'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _SharedDatePickerField(
                          hint: 'Start date',
                          value: _startDate != null
                              ? _formatSharedDate(_startDate!)
                              : null,
                          onTap: () => _pickDate(isStart: true),
                          onClear: _startDate != null
                              ? () => setState(() => _startDate = null)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SharedDatePickerField(
                          hint: 'End date',
                          value: _endDate != null
                              ? _formatSharedDate(_endDate!)
                              : null,
                          onTap: () => _pickDate(isStart: false),
                          onClear: _endDate != null
                              ? () => setState(() => _endDate = null)
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clearAll,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textSecondary(context),
                            side: BorderSide(
                              color: AppColors.borderColor(context),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Clear All'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _apply,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            context.l10nText('Apply Filters'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      context.l10nText(text),
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}

class _SharedFilterSheetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SharedFilterSheetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryDark
              : AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primaryDark
                : AppColors.borderColor(context),
          ),
        ),
        child: Text(
          context.l10nText(label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                selected ? AppColors.white : AppColors.textSecondary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SharedDatePickerField extends StatelessWidget {
  final String hint;
  final String? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _SharedDatePickerField({
    required this.hint,
    required this.value,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderColor(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? context.l10nText(hint),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: value != null
                      ? AppColors.textPrimary(context)
                      : AppColors.textTertiary(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  AppIcons.close,
                  size: 16,
                  color: AppColors.textTertiary(context),
                ),
              )
            else
              Icon(
                AppIcons.calendar_today_outlined,
                size: 16,
                color: AppColors.textTertiary(context),
              ),
          ],
        ),
      ),
    );
  }
}

class _SharedAmountFilterField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  const _SharedAmountFilterField({
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      style: TextStyle(
        color: AppColors.textPrimary(context),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: context.l10nText(hint),
        hintStyle: TextStyle(color: AppColors.textTertiary(context)),
        prefixText: '${context.l10nText('ETB')} ',
        prefixStyle: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: AppColors.surfaceColor(context),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.borderColor(context),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.borderColor(context),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? AppColors.red : AppColors.primaryLight,
          ),
        ),
      ),
    );
  }
}

class _SharedTransactionsCountHeader extends StatelessWidget {
  final int count;

  const _SharedTransactionsCountHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    final transactionLabel = count == 1
        ? context.l10nText('TRANSACTION')
        : context.l10nText('TRANSACTIONS');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 6, bottom: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderColor(context)),
        ),
      ),
      child: Text(
        '$count $transactionLabel',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.textTertiary(context),
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
      ),
    );
  }
}

class _SharedTransactionsEmptyState extends StatelessWidget {
  final bool hasQuery;

  const _SharedTransactionsEmptyState({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderColor(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primaryLight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              AppIcons.receipt_long_rounded,
              color: AppColors.primaryLight,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasQuery
                      ? context.l10nText('No matching transactions')
                      : context.l10nText('No transactions yet'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasQuery
                      ? context.l10nText('Try a different search.')
                      : context.l10nText('Group expenses will appear here.'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary(context),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatEtb(0, context),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textPrimary(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
          ),
        ],
      ),
    );
  }
}
