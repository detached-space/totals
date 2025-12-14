import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/utils/text_utils.dart';
import 'package:totals/widgets/account_detail.dart';
import 'package:totals/models/summary_models.dart';
import 'package:totals/services/account_sync_status_service.dart';
import 'package:totals/repositories/account_repository.dart';
import 'package:totals/providers/transaction_provider.dart';

class AccountsSummaryList extends StatefulWidget {
  final List<AccountSummary> accountSummaries;
  final List<String> visibleTotalBalancesForSubCards;

  const AccountsSummaryList(
      {Key? key,
      required this.accountSummaries,
      required this.visibleTotalBalancesForSubCards})
      : super(key: key);

  @override
  State<AccountsSummaryList> createState() => _AccountsSummaryListState();
}

class _AccountsSummaryListState extends State<AccountsSummaryList> {
  String isExpanded = "";
  @override
  void initState() {
    super.initState();
    print(widget.accountSummaries.length);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AccountSyncStatusService>(
      builder: (context, syncStatusService, _) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.5, // ✅ Give height
          // Add Expanded to give ListView a defined size
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: widget.accountSummaries.length,
            itemBuilder: (context, index) {
              final account = widget.accountSummaries[index];
              final syncStatus = syncStatusService.getSyncStatus(
                account.accountNumber,
                account.bankId,
              );
              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Theme.of(context).dividerColor),
                      color: Theme.of(context).cardColor,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isExpanded == "") {
                                      isExpanded = account.accountNumber;
                                    } else if (isExpanded ==
                                        account.accountNumber) {
                                      isExpanded = "";
                                    } else {
                                      isExpanded = account.accountNumber;
                                    }
                                  });
                                },
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 60,
                                      height: 60,
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.asset(
                                          AppConstants.banks
                                              .firstWhere((element) =>
                                                  element.id == account.bankId)
                                              .image,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              mainAxisSize: MainAxisSize.max,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                      AppConstants.banks
                                                          .firstWhere(
                                                              (element) =>
                                                                  element.id ==
                                                                  account
                                                                      .bankId)
                                                          .name,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurface,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      )),
                                                ),
                                                const SizedBox(width: 8),
                                                Icon(
                                                  isExpanded ==
                                                          account.accountNumber
                                                      ? Icons.keyboard_arrow_up
                                                      : Icons
                                                          .keyboard_arrow_down,
                                                )
                                              ]),
                                          Text(
                                            account.accountNumber,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Theme.of(context)
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          Text(
                                            account.accountHolderName,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Theme.of(context)
                                                  .colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          if (syncStatus != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 4.0),
                                              child: Row(
                                                children: [
                                                  SizedBox(
                                                    width: 12,
                                                    height: 12,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                              Color>(
                                                        Theme.of(context)
                                                            .colorScheme
                                                            .primary,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    syncStatus,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: Theme.of(context)
                                                          .colorScheme.primary,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Text(
                                                  widget.visibleTotalBalancesForSubCards
                                                          .contains(account
                                                              .accountNumber)
                                                      ? formatNumberWithComma(
                                                              account.balance) +
                                                          " ETB"
                                                      : "******",
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: Theme.of(context)
                                                        .colorScheme.onSurface,
                                                  )),
                                              SizedBox(
                                                width: 20,
                                              ),
                                              GestureDetector(
                                                  onTap: () {
                                                    setState(() {
                                                      if (widget
                                                          .visibleTotalBalancesForSubCards
                                                          .contains(account
                                                              .accountNumber)) {
                                                        widget
                                                            .visibleTotalBalancesForSubCards
                                                            .remove(account
                                                                .accountNumber);
                                                      } else {
                                                        widget
                                                            .visibleTotalBalancesForSubCards
                                                            .add(account
                                                                .accountNumber);
                                                      }
                                                    });
                                                  },
                                                  child: Icon(
                                                    widget.visibleTotalBalancesForSubCards
                                                            .contains(account
                                                                .accountNumber)
                                                        ? Icons.visibility_off
                                                        : Icons
                                                            .remove_red_eye_outlined,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ))
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () {
                                    _showDeleteConfirmation(context, account);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(10.0),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.red[400],
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        isExpanded == account.accountNumber
                            ? Column(
                                children: [
                                  const SizedBox(
                                    height: 20,
                                  ),
                                  Container(
                                    height: 1,
                                    color: Colors.grey[300],
                                  ),
                                  const SizedBox(
                                    height: 20,
                                  ),
                                  Container(
                                    alignment: Alignment
                                        .centerLeft, // Aligns text to the left
                                    child: Text(
                                      "Account Details",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 10,
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment
                                        .spaceBetween, // Centers horizontally
                                    children: [
                                      Text(
                                        "Total Transactions",
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme.onSurface,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                          account.totalTransactions
                                              .toInt()
                                              .toString(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Theme.of(context)
                                                .colorScheme.onSurface,
                                          )),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment
                                        .spaceBetween, // Centers horizontally
                                    children: [
                                      Text(
                                        "Total Credit",
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme.onSurface,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                          formatNumberWithComma(
                                                  account.totalCredit) +
                                              " ETB",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Theme.of(context)
                                                .colorScheme.onSurface,
                                          )),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment
                                        .spaceBetween, // Centers horizontally
                                    children: [
                                      Text(
                                        "Total Debit",
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme.onSurface,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                          formatNumberWithComma(
                                                  account.totalDebit) +
                                              " ETB",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme.onSurface,
                                            fontSize: 13,
                                          )),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    height: 1,
                                    color: Theme.of(context).dividerColor,
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment
                                        .spaceBetween, // Centers horizontally
                                    children: [
                                      Text(
                                        "Total Balance",
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme.onSurface,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                          formatNumberWithComma(
                                                  account.balance) +
                                              " ETB",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Theme.of(context)
                                                .colorScheme.onSurface,
                                          )),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double
                                        .infinity, // Makes the button take full width
                                    child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                AccountDetailPage(
                                              accountNumber:
                                                  account.accountNumber,
                                              bankId: account.bankId,
                                            ),
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                        backgroundColor:
                                            Theme.of(context).colorScheme.surfaceVariant,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        alignment: Alignment.center,
                                      ),
                                      child: Text(
                                        "Show Transaction History",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme.onSurface,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Container(),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 13,
                  )
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, AccountSummary account) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            'Delete Account',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this account?',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account Number: ${account.accountNumber}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Account Holder: ${account.accountHolderName}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bank: ${AppConstants.banks.firstWhere((element) => element.id == account.bankId).name}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This action cannot be undone.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _deleteAccount(context, account);
              },
              child: Text(
                'Delete',
                style: TextStyle(
                  color: Colors.red[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAccount(
      BuildContext context, AccountSummary account) async {
    try {
      final accountRepo = AccountRepository();
      await accountRepo.deleteAccount(account.accountNumber, account.bankId);

      // Reload data to reflect the deletion
      if (mounted) {
        Provider.of<TransactionProvider>(context, listen: false).loadData();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account deleted successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print("debug: Error deleting account: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
