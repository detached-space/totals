import 'package:flutter/material.dart';
import 'package:totals/components/custom_inputfield.dart';
import 'package:totals/data/all_banks_from_assets.dart';
import 'package:totals/models/bank.dart';
import 'package:totals/models/user_account.dart';
import 'package:totals/repositories/user_account_repository.dart';
import 'package:totals/services/bank_config_service.dart';
import 'package:totals/services/fallback_sms_parser.dart';
import 'package:totals/services/sms_config_service.dart';
import 'package:totals/widgets/inline_bank_selector.dart';
import 'package:totals/l10n/app_localizations.dart';

class AddUserAccountForm extends StatefulWidget {
  final void Function() onAccountAdded;

  const AddUserAccountForm({
    required this.onAccountAdded,
    super.key,
  });

  @override
  State<AddUserAccountForm> createState() => _AddUserAccountFormState();
}

class _AddUserAccountFormState extends State<AddUserAccountForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _accountNumber = TextEditingController();
  final TextEditingController _accountHolderName = TextEditingController();
  final BankConfigService _bankConfigService = BankConfigService();
  final SmsConfigService _smsConfigService = SmsConfigService();

  int? _selectedBankId;
  bool _isFormValid = false;
  bool _isLoadingBanks = true;
  List<Bank> _banks = [];
  Set<int> _supportedBankIds = <int>{};

  @override
  void initState() {
    super.initState();
    _accountNumber.addListener(_validateForm);
    _accountHolderName.addListener(_validateForm);
    _loadBanks();
  }

  @override
  void dispose() {
    _accountNumber.dispose();
    _accountHolderName.dispose();
    super.dispose();
  }

  List<BankSelectorOption> get _bankOptions {
    return buildBankSelectorOptions(_banks, _supportedBankIds);
  }

  bool get _hasSupportedBanks {
    return _bankOptions.any((option) => option.isSupported);
  }

  bool get _canSubmit {
    return _isFormValid && _selectedBankId != null && _hasSupportedBanks;
  }

  String _normalizeBankToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _bankDedupeKey(Bank bank) {
    final short = _normalizeBankToken(bank.shortName);
    final name = _normalizeBankToken(bank.name);
    if (short.contains('mpesa') || name.contains('mpesa')) {
      return 'mpesa';
    }
    if (short.isNotEmpty) return short;
    if (name.isNotEmpty) return name;
    return bank.image.toLowerCase();
  }

  List<Bank> _dedupeBanks(List<Bank> banks) {
    final dedupedByKey = <String, Bank>{};
    for (final bank in banks) {
      final key = _bankDedupeKey(bank);
      final existing = dedupedByKey[key];
      if (existing == null) {
        dedupedByKey[key] = bank;
        continue;
      }

      final shouldReplace = key == 'mpesa' && bank.id == 8 && existing.id != 8;
      if (shouldReplace) dedupedByKey[key] = bank;
    }
    return dedupedByKey.values.toList();
  }

  Future<Set<int>> _loadSupportedBankIds() async {
    try {
      final patterns =
          await _smsConfigService.getPatterns(allowRemoteFetch: false);
      return {
        ...patterns.map((pattern) => pattern.bankId),
        ...await FallbackSmsParser.supportedBankIds(),
      };
    } catch (e) {
      debugPrint("debug: Error loading SMS patterns: $e");
      return FallbackSmsParser.supportedBankIds();
    }
  }

  Future<void> _loadBanks() async {
    final supportedBankIds = await _loadSupportedBankIds();

    try {
      final configuredBanks = await _bankConfigService.getBanks();
      final mergedById = <int, Bank>{
        for (final bank in configuredBanks) bank.id: bank,
      };
      for (final legacyBank in AllBanksFromAssets.getAllBanks()) {
        mergedById.putIfAbsent(legacyBank.id, () => legacyBank);
      }
      final banks = _dedupeBanks(mergedById.values.toList());
      if (!mounted) return;

      setState(() {
        _banks = banks;
        _supportedBankIds = supportedBankIds;
        _selectedBankId = resolveSupportedBankId(
          banks: banks,
          supportedBankIds: supportedBankIds,
          preferredBankId: _selectedBankId,
        );
        _isLoadingBanks = false;
      });
    } catch (e) {
      debugPrint("debug: Error loading banks: $e");
      final fallbackBanks = _dedupeBanks(AllBanksFromAssets.getAllBanks());
      if (!mounted) return;

      setState(() {
        _banks = fallbackBanks;
        _supportedBankIds = supportedBankIds;
        _selectedBankId = resolveSupportedBankId(
          banks: fallbackBanks,
          supportedBankIds: supportedBankIds,
          preferredBankId: _selectedBankId,
        );
        _isLoadingBanks = false;
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate() || _selectedBankId == null) {
      return;
    }

    try {
      final accountRepo = UserAccountRepository();
      final accountExists = await accountRepo.userAccountExists(
        _accountNumber.text.trim(),
        _selectedBankId!,
      );

      if (accountExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(context.l10nTextRead('This account already exists')),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final account = UserAccount(
        accountNumber: _accountNumber.text.trim(),
        bankId: _selectedBankId!,
        accountHolderName: _accountHolderName.text.trim(),
        createdAt: DateTime.now().toIso8601String(),
      );

      await accountRepo.saveUserAccount(account);

      if (mounted) {
        Navigator.of(context).pop();
        widget.onAccountAdded();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10nTextRead('Account added successfully')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${context.l10nTextRead('Error adding account')}: $e',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _validateForm() {
    setState(() {
      _isFormValid =
          _accountHolderName.text.isNotEmpty && _accountNumber.text.isNotEmpty;
    });
  }

  Widget _buildUnsupportedBankNotice(
    BuildContext context, {
    required String message,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hintColor = colorScheme.onSurfaceVariant;

    if (_isLoadingBanks) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_banks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.account_balance_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No banks available',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).viewPadding.bottom +
              20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add Quick Access Account',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor:
                        colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Bank',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            InlineBankSelector(
              options: _bankOptions,
              selectedBankId: _selectedBankId,
              borderRadius: 12,
              onChanged: (bankId) {
                setState(() {
                  _selectedBankId = bankId;
                });
              },
            ),
            if (!_hasSupportedBanks) ...[
              const SizedBox(height: 12),
              _buildUnsupportedBankNotice(
                context,
                message:
                    'Only banks with parsing patterns can be added right now. Unsupported banks stay visible in the selector but cannot be chosen yet.',
              ),
            ],
            const SizedBox(height: 24),
            CustomTextField(
              controller: _accountNumber,
              labelText: context.l10nText('Account Number'),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return context.l10nTextRead('Enter account number');
                }
                if (value.trim().isEmpty) {
                  return context.l10nTextRead('Enter account number');
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            CustomTextField(
              controller: _accountHolderName,
              labelText: context.l10nText('Account Holder Name'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return context.l10nTextRead('Enter account holder name');
                }
                if (value.trim().isEmpty) {
                  return context.l10nTextRead('Enter account holder name');
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: hintColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(context.l10nText('Cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _canSubmit ? _submitForm : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      disabledBackgroundColor:
                          colorScheme.surfaceContainerHighest,
                      disabledForegroundColor: colorScheme.onSurfaceVariant,
                    ),
                    child: Text(
                      context.l10nText('Add Account'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
