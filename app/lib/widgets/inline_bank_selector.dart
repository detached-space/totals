import 'package:flutter/material.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/bank.dart';

class BankSelectorOption {
  final Bank bank;
  final bool isSupported;

  const BankSelectorOption({
    required this.bank,
    required this.isSupported,
  });
}

List<BankSelectorOption> buildBankSelectorOptions(
  List<Bank> banks,
  Set<int> supportedBankIds,
) {
  final sortedBanks = sortBanksAlphabetically(banks);
  return sortedBanks
      .map(
        (bank) => BankSelectorOption(
          bank: bank,
          isSupported: supportedBankIds.contains(bank.id),
        ),
      )
      .toList(growable: false);
}

List<Bank> sortBanksAlphabetically(List<Bank> banks) {
  final sorted = List<Bank>.from(banks);
  sorted.sort((a, b) {
    final shortA = a.shortName.trim().toLowerCase();
    final shortB = b.shortName.trim().toLowerCase();
    final nameA = a.name.trim().toLowerCase();
    final nameB = b.name.trim().toLowerCase();

    final primaryA = shortA.isNotEmpty ? shortA : nameA;
    final primaryB = shortB.isNotEmpty ? shortB : nameB;
    final primaryCompare = primaryA.compareTo(primaryB);
    if (primaryCompare != 0) {
      return primaryCompare;
    }

    final secondaryCompare = nameA.compareTo(nameB);
    if (secondaryCompare != 0) {
      return secondaryCompare;
    }

    return a.id.compareTo(b.id);
  });
  return sorted;
}

int? resolveSupportedBankId({
  required List<Bank> banks,
  required Set<int> supportedBankIds,
  int? preferredBankId,
}) {
  if (banks.isEmpty || supportedBankIds.isEmpty) {
    return null;
  }

  if (preferredBankId != null &&
      supportedBankIds.contains(preferredBankId) &&
      banks.any((bank) => bank.id == preferredBankId)) {
    return preferredBankId;
  }

  for (final bank in sortBanksAlphabetically(banks)) {
    if (supportedBankIds.contains(bank.id)) {
      return bank.id;
    }
  }

  return null;
}

class InlineBankSelector extends StatefulWidget {
  final List<BankSelectorOption> options;
  final int? selectedBankId;
  final ValueChanged<int> onChanged;
  final double borderRadius;

  const InlineBankSelector({
    super.key,
    required this.options,
    required this.selectedBankId,
    required this.onChanged,
    this.borderRadius = 16,
  });

  @override
  State<InlineBankSelector> createState() => _InlineBankSelectorState();
}

class _InlineBankSelectorState extends State<InlineBankSelector> {
  final TextEditingController _searchController = TextEditingController();
  bool _isExpanded = false;
  bool _showAllBanks = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BankSelectorOption> get _supportedOptions {
    return widget.options
        .where((option) => option.isSupported)
        .toList(growable: false);
  }

  bool get _canShowAllBanksToggle {
    return widget.options.length > _supportedOptions.length ||
        widget.options.length > 8;
  }

  BankSelectorOption? get _selectedOption {
    for (final option in widget.options) {
      if (option.bank.id == widget.selectedBankId) {
        return option;
      }
    }
    return null;
  }

  List<BankSelectorOption> get _filteredAllOptions {
    final supported = <BankSelectorOption>[];
    final unsupported = <BankSelectorOption>[];

    for (final option in widget.options) {
      if (!_matchesQuery(option)) continue;
      if (option.isSupported) {
        supported.add(option);
      } else {
        unsupported.add(option);
      }
    }

    return [...supported, ...unsupported];
  }

  bool _matchesQuery(BankSelectorOption option) {
    if (_query.isEmpty) {
      return true;
    }

    final normalized = _query.toLowerCase();
    final localizedName = context.l10nText(option.bank.name).toLowerCase();
    final localizedShortName =
        context.l10nText(option.bank.shortName).toLowerCase();
    return option.bank.name.toLowerCase().contains(normalized) ||
        option.bank.shortName.toLowerCase().contains(normalized) ||
        localizedName.contains(normalized) ||
        localizedShortName.contains(normalized);
  }

  void _toggleExpanded() {
    if (_supportedOptions.isEmpty) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _toggleAllBanks() {
    FocusScope.of(context).unfocus();
    setState(() {
      _showAllBanks = !_showAllBanks;
      _isExpanded = true;
      if (!_showAllBanks) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
    });
  }

  void _selectBank(BankSelectorOption option) {
    if (!option.isSupported) {
      return;
    }

    FocusScope.of(context).unfocus();
    widget.onChanged(option.bank.id);
    setState(() {
      _isExpanded = false;
      _showAllBanks = false;
      if (_query.isNotEmpty) {
        _searchController.clear();
        _query = '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selectedOption = _selectedOption;
    final hasSupportedOptions = _supportedOptions.isNotEmpty;
    final titleText = selectedOption != null
        ? context.l10nText(selectedOption.bank.name)
        : (hasSupportedOptions
            ? context.l10nText('Select a supported bank')
            : context.l10nText('No supported banks available'));
    final subtitleText = hasSupportedOptions
        ? selectedOption != null
            ? '${context.l10nText(selectedOption.bank.shortName)} · ${context.l10nText('Tap to change')}'
            : context.l10nText('Tap to browse supported banks')
        : context.l10nText('Banks without parsing patterns stay disabled');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: hasSupportedOptions ? _toggleExpanded : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasSupportedOptions
                  ? colorScheme.surface
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _isExpanded
                    ? colorScheme.primary.withValues(alpha: 0.35)
                    : colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                _BankAvatar(
                  bank: selectedOption?.bank,
                  size: 40,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titleText,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitleText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    hasSupportedOptions
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.block_rounded,
                    color: hasSupportedOptions
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: !_isExpanded
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.24,
                        ),
                        borderRadius:
                            BorderRadius.circular(widget.borderRadius),
                        border: Border.all(
                          color: colorScheme.outline.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  context.l10nText('Supported banks'),
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              // if (_canShowAllBanksToggle)
                              //   IconButton(
                              //     onPressed: _toggleAllBanks,
                              //     tooltip: _showAllBanks
                              //         ? 'Hide all banks'
                              //         : 'Browse all banks',
                              //     icon: Icon(
                              //       _showAllBanks
                              //           ? Icons.close_rounded
                              //           : Icons.grid_view_rounded,
                              //     ),
                              //   ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 116,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _supportedOptions.length,
                              separatorBuilder: (context, index) {
                                return const SizedBox(width: 12);
                              },
                              itemBuilder: (context, index) {
                                return _buildOptionCard(
                                  _supportedOptions[index],
                                  width: 104,
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  context.l10nText(
                                    'Only banks with SMS parsing support can be selected right now.',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_showAllBanks) ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: _searchController,
                              onChanged: (value) {
                                setState(() {
                                  _query = value.trim();
                                });
                              },
                              decoration: InputDecoration(
                                hintText: context.l10nText('Search banks'),
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        onPressed: _clearSearch,
                                        icon: const Icon(Icons.close),
                                      ),
                                isDense: true,
                                filled: true,
                                fillColor: colorScheme.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: colorScheme.outline.withValues(
                                      alpha: 0.18,
                                    ),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: colorScheme.outline.withValues(
                                      alpha: 0.18,
                                    ),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_filteredAllOptions.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                child: Center(
                                  child: Text(
                                    context.l10nText(
                                      'No banks match your search.',
                                    ),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              )
                            else
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final width = constraints.maxWidth;
                                  final crossAxisCount = width >= 520
                                      ? 4
                                      : width >= 360
                                          ? 3
                                          : 2;

                                  return GridView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: _filteredAllOptions.length,
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: crossAxisCount,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: 0.82,
                                    ),
                                    itemBuilder: (context, index) {
                                      return _buildOptionCard(
                                        _filteredAllOptions[index],
                                        showFullName: true,
                                        showUnsupportedBadge: true,
                                      );
                                    },
                                  );
                                },
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildOptionCard(
    BankSelectorOption option, {
    double? width,
    bool showFullName = false,
    bool showUnsupportedBadge = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = option.bank.id == widget.selectedBankId;

    Widget child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: option.isSupported ? () => _selectBank(option) : null,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.1)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.outline.withValues(alpha: 0.18),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BankAvatar(
                bank: option.bank,
                size: 46,
              ),
              const SizedBox(height: 10),
              Text(
                context.l10nText(option.bank.shortName),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (showFullName) ...[
                const SizedBox(height: 4),
                Text(
                  context.l10nText(option.bank.name),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (showUnsupportedBadge && !option.isSupported) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    context.l10nText('Unsupported'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (!option.isSupported) {
      child = Opacity(
        opacity: 0.45,
        child: child,
      );
    }

    return Tooltip(
      message: context.l10nText(option.bank.name),
      child: child,
    );
  }
}

class _BankAvatar extends StatelessWidget {
  final Bank? bank;
  final double size;

  const _BankAvatar({
    required this.bank,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: ClipOval(
        child: bank == null
            ? Container(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.account_balance,
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : Image.asset(
                bank!.image,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.account_balance,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
      ),
    );
  }
}
