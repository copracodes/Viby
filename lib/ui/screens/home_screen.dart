import 'package:flutter/material.dart';

/// Placeholder home screen.
///
/// This is intentionally feature-free — it only proves the app boots and the
/// router resolves. Real library / player UI lands in later phases.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Viby')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.graphic_eq,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Viby', style: text.headlineMedium),
            const SizedBox(height: 8),
            Text('Scaffold ready.', style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}
