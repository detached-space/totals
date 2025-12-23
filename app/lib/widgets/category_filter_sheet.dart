import 'package:flutter/material.dart';
import 'package:totals/models/category.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/category_icons.dart';

class _CategoryFilterOption {
  final int? id;
  final String name;
  final IconData icon;
  final String? subtitle;

  const _CategoryFilterOption({
    required this.id,
    required this.name,
    required this.icon,
    this.subtitle,
  });
}

Future<Set<int?>?> showCategoryFilterSheet({
  required BuildContext context,
  required TransactionProvider provider,
  required Set<int?> selectedCategoryIds,
  String title = 'Filter categories',
  String? flow,
  bool includeUncategorized = true,
}) async {
  final themed = Theme.of(context);
  final filtered = flow == null
      ? provider.categories
      : provider.categories
          .where((c) => c.flow.toLowerCase() == flow.toLowerCase())
          .toList(growable: false);
  final categories = filtered.isEmpty ? provider.categories : filtered;

  final options = <_CategoryFilterOption>[];
  if (includeUncategorized) {
    options.add(
      const _CategoryFilterOption(
        id: null,
        name: 'Uncategorized',
        icon: Icons.label_off_rounded,
        subtitle: 'No category assigned',
      ),
    );
  }

  for (final category in categories) {
    if (category.id == null) continue;
    options.add(
      _CategoryFilterOption(
        id: category.id,
        name: category.name,
        icon: iconForCategoryKey(category.iconKey),
        subtitle: category.typeLabel(),
      ),
    );
  }

  final optionIds = options.map((option) => option.id).toSet();
  final workingSelection =
      selectedCategoryIds.where((id) => optionIds.contains(id)).toSet();

  return showModalBottomSheet<Set<int?>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          void toggleSelection(int? id) {
            setSheetState(() {
              if (workingSelection.contains(id)) {
                workingSelection.remove(id);
              } else {
                workingSelection.add(id);
              }
            });
          }

          void selectAll() {
            setSheetState(() {
              workingSelection
                ..clear()
                ..addAll(optionIds);
            });
          }

          void clearAll() {
            setSheetState(workingSelection.clear);
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: themed.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: selectAll,
                          child: const Text('Select all'),
                        ),
                        TextButton(
                          onPressed: clearAll,
                          child: const Text('Unselect all'),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: themed.colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            themed.colorScheme.onSurfaceVariant.withOpacity(0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.filter_list_rounded,
                          size: 18,
                          color: themed.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${workingSelection.length} selected',
                          style: TextStyle(
                            fontSize: 13,
                            color: themed.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.6,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final selected = workingSelection.contains(option.id);
                        return ListTile(
                          leading: Icon(option.icon),
                          title: Text(option.name),
                          subtitle: option.subtitle == null
                              ? null
                              : Text(option.subtitle!),
                          trailing: Checkbox(
                            value: selected,
                            onChanged: (_) => toggleSelection(option.id),
                          ),
                          onTap: () => toggleSelection(option.id),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, workingSelection),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themed.colorScheme.primary,
                          foregroundColor: themed.colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Apply filters'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
