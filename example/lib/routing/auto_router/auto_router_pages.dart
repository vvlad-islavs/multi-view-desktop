import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../../l10n/example_localizations.dart';
import 'app_router.dart';

@RoutePage()
class AutoCatalogPage extends StatelessWidget {
  const AutoCatalogPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = ExampleLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.autoCatalogTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.autoCatalogBody),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.router.push(const AutoItemRoute()),
              child: Text(l10n.nextRoute),
            ),
          ],
        ),
      ),
    );
  }
}

@RoutePage()
class AutoItemPage extends StatelessWidget {
  const AutoItemPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = ExampleLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.autoItemTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.autoItemBody),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => context.router.maybePop(), child: Text(l10n.backRoute)),
          ],
        ),
      ),
    );
  }
}
