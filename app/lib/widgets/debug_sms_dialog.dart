import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/services/sms_service.dart';
import 'package:totals/widgets/failed_parse_dialog.dart';

Future<void> showDebugSmsDialog(BuildContext context) async {
  final TextEditingController addressController = TextEditingController();
  final TextEditingController bodyController = TextEditingController();

  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Simulate SMS"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: "Sender (e.g. CBE)"),
            ),
            TextField(
              controller: bodyController,
              decoration: const InputDecoration(labelText: "Message Body"),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await showFailedParseDialog(context);
            },
            child: const Text("View Failed"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final address = addressController.text;
              final body = bodyController.text;
              if (await SmsService.isRelevantMessage(address)) {
                await SmsService.processMessage(body, address,
                    messageDate: DateTime.now());
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("SMS Logged Successfully")),
                  );
                  Provider.of<TransactionProvider>(context, listen: false)
                      .loadData();
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Ignored: Sender not recognized")),
                  );
                }
              }
            },
            child: const Text("Simulate"),
          ),
        ],
      );
    },
  );
}
