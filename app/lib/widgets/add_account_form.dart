import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/components/custom_inputfield.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/services/account_registration_service.dart';
import 'package:totals/providers/transaction_provider.dart';

class RegisterAccountForm extends StatefulWidget {
  final void Function() onSubmit;
  final int? initialBankId;

  const RegisterAccountForm({
    required this.onSubmit,
    this.initialBankId,
    super.key,
  });

  @override
  State<RegisterAccountForm> createState() => _RegisterAccountFormState();
}

class _RegisterAccountFormState extends State<RegisterAccountForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _accountNumber = TextEditingController();
  final TextEditingController _accountHolderName = TextEditingController();
  late int selected_bank;
  bool isFormValid = false;
  bool syncPreviousSms = true;

  @override
  void initState() {
    super.initState();
    // Use initial bank ID if provided, otherwise default to 1 (CBE)
    selected_bank = widget.initialBankId ?? 1;
  }

  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      try {
        final service = AccountRegistrationService();
        final provider =
            Provider.of<TransactionProvider>(context, listen: false);

        // Create account immediately (don't await sync)
        final account = await service.registerAccount(
          accountNumber: _accountNumber.text,
          accountHolderName: _accountHolderName.text,
          bankId: selected_bank,
          syncPreviousSms: syncPreviousSms,
          onSyncComplete: () {
            // Reload data when sync completes
            provider.loadData();
          },
        );

        if (account != null && mounted) {
          // Refresh data to show new account
          provider.loadData();
          // Close drawer immediately
          widget.onSubmit();
          Navigator.pop(context);
          // Sync will continue in background and update status in account cards
        }
      } catch (e) {
        print("debug: Error registering account: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error registering account: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _validateForm() {
    setState(() {
      isFormValid =
          _accountHolderName.text.isNotEmpty && _accountNumber.text.isNotEmpty
              ? true
              : false;
    });
  }

  void _showBankSelectionModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  "Select Bank",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: AppConstants.banks.length,
                  itemBuilder: (context, index) {
                    final bank = AppConstants.banks[index];
                    final isSelected = selected_bank == bank.id;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          selected_bank = bank.id;
                        });
                        Navigator.pop(context);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.1)
                              : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .outline
                                    .withOpacity(0.2),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  bank.image,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              bank.shortName, // Use shortName for Grid
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedBankData =
        AppConstants.banks.firstWhere((element) => element.id == selected_bank);

    return Form(
      key: _formKey,
      onChanged: _validateForm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Add New Account",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Enter your bank details below",
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.close,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceVariant
                      .withOpacity(0.3),
                  shape: const CircleBorder(),
                ),
              )
            ],
          ),
          const SizedBox(height: 32),

          // Bank Selector
          Text(
            "Bank",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _showBankSelectionModal,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.withOpacity(0.1)),
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        selectedBankData.image,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      selectedBankData.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          CustomTextField(
            controller: _accountNumber,
            labelText: "Account Number",
            keyboardType: TextInputType.number,
            validator: (value) => (value == null || value.isEmpty)
                ? "Enter account number"
                : null,
          ),
          const SizedBox(height: 20),
          CustomTextField(
            controller: _accountHolderName,
            labelText: "Account Holder Name",
            validator: (value) => (value == null || value.isEmpty)
                ? "Enter account holder name"
                : null,
          ),

          const SizedBox(height: 24),

          // Sync Switch
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.sms_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Sync SMS History",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        "Import past transactions",
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: syncPreviousSms,
                  onChanged: (value) {
                    setState(() {
                      syncPreviousSms = value;
                    });
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),

          const SizedBox(
              height:
                  32), // Push buttons down with fixed spacing instead of Spacer

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  child: const Text("Cancel"),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: isFormValid ? _submitForm : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    disabledBackgroundColor:
                        Theme.of(context).colorScheme.surfaceVariant,
                    disabledForegroundColor:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  child: const Text(
                    "Save Account",
                    style: TextStyle(
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
    );
  }
}
