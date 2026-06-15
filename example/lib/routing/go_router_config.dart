import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/example_localizations.dart';

/// GoRouter tree for the secondary window demo (browse + item).
GoRouter createDemoGoRouter() {
  return GoRouter(
    initialLocation: '/browse',
    routes: [
      GoRoute(
        path: '/browse',
        builder: (context, state) => const _GoBrowsePage(),
        routes: [
          GoRoute(
            path: 'item',
            builder: (context, state) => const _GoItemPage(),
          ),
        ],
      ),
    ],
  );
}

class _GoBrowsePage extends StatelessWidget {
  const _GoBrowsePage();

  @override
  Widget build(BuildContext context) {
    final l10n = ExampleLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.goBrowseTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.goBrowseBody),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go('/browse/item'), child: Text(l10n.nextRoute)),
          ],
        ),
      ),
    );
  }
}

class _GoItemPage extends StatelessWidget {
  const _GoItemPage();

  @override
  Widget build(BuildContext context) {
    final l10n = ExampleLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.goItemTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.goItemBody),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => context.go('/browse'), child: Text(l10n.backRoute)),
          ],
        ),
      ),
    );
  }
}
