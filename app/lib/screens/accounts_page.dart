import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:totals/repositories/user_account_repository.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/user_account.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/widgets/add_user_account_form.dart';
import 'package:totals/screens/account_share_qr_page.dart';
import 'package:totals/screens/account_share_scan_page.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/utils/account_sort.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final UserAccountRepository _userAccountRepo = UserAccountRepository();
  final BankConfigService _bankConfigService = BankConfigService();
  final TextEditingController _searchController = TextEditingController();
  List<Bank> _banks = [];
  List<UserAccount> _userAccounts = [];
  String _searchQuery = '';
  int? _selectedBankId;
  bool _isLoading = true;
  Set<String> _selectedKeys = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final configuredBanks = await _bankConfigService.getBanks();
      final mergedBanksById = <int, Bank>{
        for (final bank in configuredBanks) bank.id: bank,
      };
      for (final legacyBank in AllBanksFromAssets.getAllBanks()) {
        mergedBanksById.putIfAbsent(legacyBank.id, () => legacyBank);
      }
      _banks = mergedBanksById.values.toList();

      // Load user accounts
      final accounts = await _userAccountRepo.getUserAccounts();
      final sortedAccounts = List<UserAccount>.from(accounts)
        ..sort(_compareUserAccounts);

      if (mounted) {
        setState(() {
          _userAccounts = sortedAccounts;
          final accountKeys = sortedAccounts.map(_accountKey).toSet();
          final accountBankIds =
              sortedAccounts.map((account) => account.bankId).toSet();
          _selectedKeys = _selectedKeys.intersection(accountKeys);
          if (!accountBankIds.contains(_selectedBankId)) {
            _selectedBankId = null;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        print("debug: Error loading data: $e");
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Bank? _getBankInfo(int bankId) {
    try {
      return _banks.firstWhere((element) => element.id == bankId);
    } catch (e) {
      return null;
    }
  }

  String _accountKey(UserAccount account) {
    return '${account.bankId}:${account.accountNumber}';
  }

  int _compareUserAccounts(UserAccount a, UserAccount b) {
    return compareAccountDisplayFields(
      leftBankId: a.bankId,
      rightBankId: b.bankId,
      leftHolderName: a.accountHolderName,
      rightHolderName: b.accountHolderName,
      leftAccountNumber: a.accountNumber,
      rightAccountNumber: b.accountNumber,
      bankNameForId: (bankId) {
        final bank = _getBankInfo(bankId);
        return bank?.name ?? bank?.shortName ?? 'Bank $bankId';
      },
    );
  }

  List<UserAccount> _filterAccounts(List<UserAccount> accounts) {
    return accounts.where((account) {
      if (_selectedBankId != null && account.bankId != _selectedBankId) {
        return false;
      }
      if (_searchQuery.isEmpty) return true;

      final bank = _getBankInfo(account.bankId);
      final bankName = bank?.name.toLowerCase() ?? '';
      final bankShortName = bank?.shortName.toLowerCase() ?? '';
      final accountNumber = account.accountNumber.toLowerCase();
      final holderName = account.accountHolderName.toLowerCase();
      final query = _searchQuery;
      return accountNumber.contains(query) ||
          holderName.contains(query) ||
          bankName.contains(query) ||
          bankShortName.contains(query);
    }).toList();
  }

  List<int> get _availableBankIds {
    final bankIds = _userAccounts.map((account) => account.bankId).toSet();
    return bankIds.toList(growable: false)
      ..sort((left, right) {
        final leftBank = _getBankInfo(left);
        final rightBank = _getBankInfo(right);
        final comparison = compareDisplayText(
          leftBank?.shortName ?? leftBank?.name ?? 'Bank $left',
          rightBank?.shortName ?? rightBank?.name ?? 'Bank $right',
        );
        return comparison != 0 ? comparison : left.compareTo(right);
      });
  }

  void _selectBank(int? bankId) {
    FocusScope.of(context).unfocus();
    setState(() => _selectedBankId = bankId);
  }

  void _clearFilters() {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() => _selectedBankId = null);
  }

  bool get _isSelectionMode => _selectedKeys.isNotEmpty;

  List<UserAccount> get _selectedAccounts {
    return _userAccounts
        .where((account) => _selectedKeys.contains(_accountKey(account)))
        .toList();
  }

  void _toggleSelection(UserAccount account) {
    final key = _accountKey(account);
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedKeys.clear();
    });
  }

  void _selectAll(List<UserAccount> accounts) {
    setState(() {
      _selectedKeys = accounts.map(_accountKey).toSet();
    });
  }

  Future<void> _copyAccountNumber(String accountNumber) async {
    await Clipboard.setData(ClipboardData(text: accountNumber));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.l10nTextRead('Account number copied to clipboard')),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showAddAccountDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Container(
            height: mediaQuery.size.height * 0.85,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: AddUserAccountForm(
                onAccountAdded: () {
                  _loadData();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteSelected() async {
    final selected = _selectedAccounts;
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(dialogContext.l10nText('Delete Selected Accounts?')),
          content: Text(
            '${dialogContext.l10nText('Are you sure you want to delete')} ${selected.length} ${dialogContext.l10nText(selected.length == 1 ? 'account' : 'accounts')}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.l10nText('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(dialogContext.l10nText('Delete')),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        for (final account in selected) {
          if (account.id != null) {
            await _userAccountRepo.deleteUserAccount(account.id!);
          } else {
            await _userAccountRepo.deleteUserAccountByNumberAndBank(
              account.accountNumber,
              account.bankId,
            );
          }
        }
        _clearSelection();
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${context.l10nTextRead('Deleted')} ${selected.length} ${context.l10nTextRead(selected.length == 1 ? 'account' : 'accounts')}',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${context.l10nTextRead('Error deleting accounts')}: $e',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _openShareQr() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AccountShareQrPage(),
      ),
    );
  }

  Future<void> _openScanQr() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AccountShareScanPage(),
      ),
    );
    if (result == true) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final filteredAccounts = _filterAccounts(_userAccounts);
    final availableBankIds = _availableBankIds;
    final hasActiveFilters = _searchQuery.isNotEmpty || _selectedBankId != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        leading: _isSelectionMode
            ? IconButton(
                tooltip: context.l10nText('Clear selection'),
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,
        title: Text(
          _isSelectionMode
              ? '${_selectedKeys.length} ${context.l10nText('selected')}'
              : context.l10nText('Quick Access Accounts'),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: _isSelectionMode
            ? [
                IconButton(
                  tooltip: context.l10nText('Clear selection'),
                  icon: const Icon(Icons.clear_all),
                  onPressed: _clearSelection,
                ),
                IconButton(
                  tooltip: context.l10nText('Select all'),
                  icon: const Icon(Icons.select_all),
                  onPressed: () => _selectAll(filteredAccounts),
                ),
                IconButton(
                  tooltip: context.l10nText('Delete selected'),
                  icon: const Icon(Icons.delete_outline),
                  color: colorScheme.error,
                  onPressed: _confirmDeleteSelected,
                ),
              ]
            : [
                IconButton(
                  tooltip: context.l10nText('Share accounts'),
                  icon: const Icon(Icons.qr_code_rounded),
                  onPressed: _openShareQr,
                ),
              ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: TextField(
              controller: _searchController,
              autofocus: false,
              decoration: InputDecoration(
                hintText: context.l10nText('Search accounts...'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceVariant.withOpacity(0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          if (!_isLoading && availableBankIds.isNotEmpty) ...[
            SizedBox(
              height: 42,
              child: ListView.separated(
                key: const ValueKey<String>(
                  'quick-access-bank-filter-list',
                ),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: availableBankIds.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _BankFilterChip(
                      key: const ValueKey<String>(
                        'quick-access-bank-filter-all',
                      ),
                      label: context.l10nText('All Banks'),
                      selected: _selectedBankId == null,
                      onSelected: () => _selectBank(null),
                    );
                  }

                  final bankId = availableBankIds[index - 1];
                  final bank = _getBankInfo(bankId);
                  return _BankFilterChip(
                    key: ValueKey<String>(
                      'quick-access-bank-filter-$bankId',
                    ),
                    label: context.l10nText(
                      bank?.shortName ?? bank?.name ?? 'Bank $bankId',
                    ),
                    selected: _selectedBankId == bankId,
                    onSelected: () => _selectBank(bankId),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Accounts list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredAccounts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              hasActiveFilters
                                  ? Icons.search_off
                                  : Icons.account_balance_outlined,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              hasActiveFilters
                                  ? context.l10nText('No accounts found')
                                  : context.l10nText('No accounts yet'),
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (!hasActiveFilters)
                              Text(
                                context.l10nText(
                                  'Tap + to add your first account',
                                ),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (hasActiveFilters)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: TextButton.icon(
                                  onPressed: _clearFilters,
                                  icon: const Icon(Icons.filter_alt_off),
                                  label: Text(
                                    context.l10nText('Clear filters'),
                                  ),
                                ),
                              ),
                            if (!hasActiveFilters)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: OutlinedButton.icon(
                                  onPressed: _openScanQr,
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: Text(
                                    context.l10nText('Scan account QR'),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filteredAccounts.length,
                          itemBuilder: (context, index) {
                            final account = filteredAccounts[index];
                            final bank = _getBankInfo(account.bankId);
                            return _AccountCard(
                              account: account,
                              bank: bank,
                              isSelected:
                                  _selectedKeys.contains(_accountKey(account)),
                              isSelectionMode: _isSelectionMode,
                              onTap: _isSelectionMode
                                  ? () => _toggleSelection(account)
                                  : null,
                              onLongPress: () {
                                _toggleSelection(account);
                              },
                              onCopy: () =>
                                  _copyAccountNumber(account.accountNumber),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: _isSelectionMode
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: 'scan-accounts-fab',
                  onPressed: _openScanQr,
                  child: const Icon(Icons.camera_alt),
                ),
                const SizedBox(width: 12),
                FloatingActionButton(
                  heroTag: 'add-account-fab',
                  onPressed: _showAddAccountDialog,
                  child: const Icon(Icons.add),
                ),
              ],
            ),
    );
  }
}

class _BankFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _BankFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      selectedColor: colorScheme.primaryContainer,
      backgroundColor: colorScheme.surface,
      side: BorderSide(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.5)
            : colorScheme.outline.withValues(alpha: 0.25),
      ),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final UserAccount account;
  final Bank? bank;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;
  final VoidCallback onCopy;

  const _AccountCard({
    required this.account,
    this.bank,
    required this.isSelected,
    required this.isSelectionMode,
    this.onTap,
    required this.onLongPress,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final selectionColor = colorScheme.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected ? selectionColor.withOpacity(0.06) : null,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? selectionColor
              : colorScheme.outline.withOpacity(0.2),
          width: isSelected ? 1.2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Bank icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: bank != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              bank!.image,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: colorScheme.surfaceVariant,
                                  child: Icon(
                                    Icons.account_balance,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                );
                              },
                            ),
                          )
                        : Icon(
                            Icons.account_balance,
                            color: colorScheme.onSurfaceVariant,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.accountHolderName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10nText(
                            bank?.shortName ?? bank?.name ?? 'Unknown Bank',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          account.accountNumber,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelectionMode)
                    Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: isSelected ? selectionColor : colorScheme.outline,
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.copy_outlined),
                      onPressed: onCopy,
                      tooltip: context.l10nText('Copy account number'),
                      color: colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
