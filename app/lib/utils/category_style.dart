import 'package:flutter/material.dart';
import 'package:totals/models/category.dart';

Color categoryTypeColor(Category category, BuildContext context) {
  if (category.uncategorized) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
  final isIncome = category.flow.toLowerCase() == 'income';
  if (isIncome) {
    return category.essential ? Colors.green : Colors.teal;
  }
  return category.essential ? Colors.blue : Colors.orange;
}
