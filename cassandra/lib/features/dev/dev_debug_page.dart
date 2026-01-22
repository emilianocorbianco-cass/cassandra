import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DevDebugPage extends StatelessWidget {
  final Future<void> Function() onResetHistory;
  final Future<void> Function() onRegenDemo;
  final Future<void> Function() onAddRecovered;
  final Future<void> Function() onAddVoid;

  const DevDebugPage({
    super.key,
    required this.onResetHistory,
    required this.onRegenDemo,
    required this.onAddRecovered,
    required this.onAddVoid,
  });

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('Debug non disponibile in release build')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Debug')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Strumenti di debug (solo debug build).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              () async => onResetHistory();
            },
            child: const Text('Reset storico'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              () async => onRegenDemo();
            },
            child: const Text('Rigenera demo (seed)'),
          ),
          const Divider(height: 32),
          OutlinedButton(
            onPressed: () {
              () async => onAddRecovered();
            },
            child: const Text('+ recuperata <48h'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              () async => onAddVoid();
            },
            child: const Text('+ nulla >48h'),
          ),
        ],
      ),
    );
  }
}
