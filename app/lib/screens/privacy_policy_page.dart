import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:totals/l10n/app_localizations.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const String _assetPath = 'PRIVACY_POLICY.md';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10nText('Privacy Policy')),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(_assetPath),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.l10nText(
                    'Could not load the privacy policy right now.',
                  ),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            );
          }

          return SelectionArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: _buildContent(context, snapshot.data!),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, String markdown) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];

    for (final rawLine in markdown.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 10));
        continue;
      }

      if (trimmed.startsWith('# ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.l10nText(trimmed.substring(2)),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        continue;
      }

      if (trimmed.startsWith('## ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Text(
              context.l10nText(trimmed.substring(3)),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
        continue;
      }

      if (trimmed.startsWith('- ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10nText(trimmed.substring(2)),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      final isMetaLine = trimmed.startsWith('Effective date:');
      final text = context.l10nText(trimmed);
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text,
            style: isMetaLine
                ? theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ),
      );
    }

    return widgets;
  }
}
