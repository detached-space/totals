import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:totals/data/consts.dart';
import 'package:totals/main.dart';

class BanksSummaryList extends StatelessWidget {
  final List<BankSummary> banks;

  BanksSummaryList({required this.banks});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      // Add Expanded to give ListView a defined size
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: banks.length,
        itemBuilder: (context, index) {
          final bank = banks[index];
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          AppConstants.banks
                              .firstWhere(
                                  (element) => element.id == bank.bankId)
                              .image,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(
                      width: 16,
                    ),
                    Container(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppConstants.banks
                                .firstWhere(
                                    (element) => element.id == bank.bankId)
                                .name,
                            style: const TextStyle(
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            bank.accountCount.toString() + ' accounts',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                              (bank.totalCredit - bank.totalDebit)
                                      .toStringAsFixed(2) +
                                  " ETB",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              )),
                        ],
                      ),
                    ),
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
