import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/main.dart';
import 'package:totals/widgets/account_detail.dart';

class AccountsSummaryList extends StatefulWidget {
  final List<AccountSummary> accountSummaries;

  AccountsSummaryList({Key? key, required this.accountSummaries})
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
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5, // ✅ Give height
      // Add Expanded to give ListView a defined size
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.accountSummaries.length,
        itemBuilder: (context, index) {
          final account = widget.accountSummaries[index];
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                  color: Colors.white,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 60,
                          height: 60,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              AppConstants.banks
                                  .firstWhere(
                                      (element) => element.id == account.bankId)
                                  .image,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Container(
                          child: Row(
                            children: [
                              Container(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                              AppConstants.banks
                                                  .firstWhere((element) =>
                                                      element.id ==
                                                      account.bankId)
                                                  .name,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF444750),
                                              )),
                                          GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  if (isExpanded == "") {
                                                    isExpanded =
                                                        account.accountNumber;
                                                  } else if (isExpanded ==
                                                      account.accountNumber) {
                                                    isExpanded = "";
                                                  } else {
                                                    isExpanded =
                                                        account.accountNumber;
                                                  }
                                                });
                                              },
                                              child: Icon(
                                                isExpanded ==
                                                        account.accountNumber
                                                    ? Icons.arrow_drop_up
                                                    : Icons.arrow_drop_down,
                                                size: 28,
                                              ))
                                        ]),
                                    Text(
                                      account.accountNumber,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      account.accountHolderName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                        (account.totalCredit -
                                                    account.totalDebit)
                                                .toStringAsFixed(2) +
                                            " ETB",
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF444750),
                                        )),
                                  ],
                                ),
                              ),
                            ],
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
                                child: const Text(
                                  "Account Details",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF444750),
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
                                      color: Colors.grey[500],
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                      account.totalTransactions
                                          .toInt()
                                          .toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
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
                                      color: Colors.grey[500],
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(account.totalCredit.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
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
                                      color: Colors.grey[500],
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(account.totalDebit.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      )),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment
                                    .spaceBetween, // Centers horizontally
                                children: [
                                  Text(
                                    "Pending Credit",
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(account.pendingCredit.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      )),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment
                                    .spaceBetween, // Centers horizontally
                                children: [
                                  Text(
                                    "Settled Balance",
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(account.settledBalance.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      )),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                height: 1,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment
                                    .spaceBetween, // Centers horizontally
                                children: [
                                  Text(
                                    "Total Balance",
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(account.totalCredit.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
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
                                        builder: (context) => AccountDetailPage(
                                          accountNumber: account.accountNumber,
                                          bankId: account.bankId,
                                        ),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    backgroundColor: Color(0xffF1F4FF),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                  ),
                                  child: const Text(
                                    "Show Transaction History",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF444750),
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
  }
}
