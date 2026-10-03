import 'package:flutter/material.dart';

import 'empty_state.dart';

void showComingSoon(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('Coming in the next update')),
    );
}

/// Placeholder for tabs that are not built yet.
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const EmptyState(
        icon: Icons.construction,
        title: 'Coming soon',
        message: 'This section is being built.',
      ),
    );
  }
}
