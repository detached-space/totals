import 'package:flutter/material.dart';
import 'package:totals/screens/failed_parses_page.dart';

Future<void> showFailedParseDialog(BuildContext context) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const FailedParsesPage()),
  );
}
