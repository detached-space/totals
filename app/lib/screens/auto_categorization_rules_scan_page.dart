import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:totals/l10n/app_localizations.dart';
import 'package:totals/models/category.dart';
import 'package:totals/providers/transaction_provider.dart';
import 'package:totals/utils/auto_categorization_rules_share_payload.dart';

class AutoCategorizationRulesScanPage extends StatefulWidget {
  const AutoCategorizationRulesScanPage({super.key});

  @override
  State<AutoCategorizationRulesScanPage> createState() =>
      _AutoCategorizationRulesScanPageState();
}

class _AutoCategorizationRulesScanPageState
    extends State<AutoCategorizationRulesScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null || rawValue.isEmpty) continue;
      final payload = AutoCategorizationRulesSharePayload.decode(rawValue);
      if (payload == null) continue;

      setState(() {
        _isProcessing = true;
      });
      await _controller.stop();

      if (!mounted) return;
      final provider = Provider.of<TransactionProvider>(
        context,
        listen: false,
      );
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _AutoCategorizationImportPreviewSheet(
          payload: payload,
        ),
      );

      if (confirmed == true) {
        final result =
            await provider.importAutoCategorizationRulesPayload(payload);
        if (!mounted) return;
        Navigator.of(context).pop(result);
        return;
      }

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
      });
      await _controller.start();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Text(context.l10nText('Scan Auto-Category Rules')),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    context.l10nText(
                      'Camera unavailable. Please enable permissions.',
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isProcessing
                          ? context.l10nText('Importing rules...')
                          : context.l10nText(
                              'Point your camera at a Totals auto-category QR.',
                            ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoCategorizationImportPreviewSheet extends StatelessWidget {
  final AutoCategorizationRulesSharePayload payload;

  const _AutoCategorizationImportPreviewSheet({
    required this.payload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = Provider.of<TransactionProvider>(context, listen: false);
    final categoriesToCreate = _categoriesToCreate(
      payload.categories,
      provider.categories,
    );
    final ruleGroups = _countRuleGroups(payload.rules);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10nText('Import auto-category rules?'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10nText(
                'Rules for the same counterparty will be updated. Missing categories will be created first.',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _ImportPreviewStat(
              icon: Icons.rule_folder_outlined,
              label: context.l10nText('Rule groups'),
              value: '$ruleGroups',
            ),
            const SizedBox(height: 10),
            _ImportPreviewStat(
              icon: Icons.category_outlined,
              label: context.l10nText('Categories to create'),
              value: '${categoriesToCreate.length}',
            ),
            if (categoriesToCreate.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in categoriesToCreate.take(8))
                    Chip(
                      label: Text(category.name),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (categoriesToCreate.length > 8)
                    Chip(
                      label: Text('+${categoriesToCreate.length - 8}'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(context.l10nText('Cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(context.l10nText('Import')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _countRuleGroups(List<AutoCategorizationRulesShareRule> rules) {
    final groups = <String>{};
    for (final rule in rules) {
      groups.add('${rule.normalizedCounterparty}:${rule.flow}');
    }
    return groups.length;
  }

  List<AutoCategorizationRulesShareCategory> _categoriesToCreate(
    List<AutoCategorizationRulesShareCategory> sharedCategories,
    List<Category> localCategories,
  ) {
    final result = <AutoCategorizationRulesShareCategory>[];
    final seen = <int>{};
    for (final sharedCategory in sharedCategories) {
      if (!seen.add(sharedCategory.sourceId)) continue;
      if (_findMatchingCategory(sharedCategory, localCategories) == null) {
        result.add(sharedCategory);
      }
    }
    return result;
  }

  Category? _findMatchingCategory(
    AutoCategorizationRulesShareCategory sharedCategory,
    List<Category> localCategories,
  ) {
    final builtInKey = sharedCategory.builtInKey?.trim();
    if (builtInKey != null && builtInKey.isNotEmpty) {
      for (final category in localCategories) {
        if (category.builtInKey == builtInKey) return category;
      }
    }

    final targetFlow = _normalizeFlow(sharedCategory.flow);
    final targetName = _normalizeName(sharedCategory.name);
    for (final category in localCategories) {
      if (_normalizeFlow(category.flow) != targetFlow) continue;
      if (_normalizeName(category.name) == targetName) return category;
    }
    return null;
  }

  String _normalizeFlow(String? flow) {
    return flow?.trim().toLowerCase() == 'income' ? 'income' : 'expense';
  }

  String _normalizeName(String name) {
    return name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }
}

class _ImportPreviewStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ImportPreviewStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
