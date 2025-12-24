import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/models/transaction.dart';

class DebugTransactionsDialog extends StatelessWidget {
  const DebugTransactionsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TransactionProvider>(
      builder: (context, provider, child) {
        final transactions = provider.allTransactions; // Get ALL, not filtered
        return AlertDialog(
          title: Text("Stored Transactions (${transactions.length})"),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.separated(
              itemCount: transactions.length,
              separatorBuilder: (ctx, i) => const Divider(),
              itemBuilder: (context, index) {
                final t = transactions[index];
                return ListTile(
                  title: Text(
                    "Bank(${t.bankId})'} - ${t.reference ?? 'No Ref'}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Amount: ${t.amount} ${t.type}"),
                      Text(
                          "Acct: '${t.accountNumber}'"), // Quote to see empty strings
                      Text("Time: ${t.time}"),
                      Text("Bal: ${t.currentBalance}"),
                    ],
                  ),
                  trailing: Icon(
                    t.type == 'CREDIT'
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                    color: t.type == 'CREDIT' ? Colors.green : Colors.red,
                    size: 16,
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                provider.loadData();
              },
              child: const Text("Refresh Data"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }
}

Future<void> showDebugTransactionsDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (context) => const DebugTransactionsDialog(),
  );
}
