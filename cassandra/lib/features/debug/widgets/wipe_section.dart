import 'package:flutter/material.dart';

import '../cold_test_service.dart';

class WipeSection extends StatefulWidget {
  const WipeSection({super.key});

  @override
  State<WipeSection> createState() => _WipeSectionState();
}

class _WipeSectionState extends State<WipeSection> {
  final _service = ColdTestService();
  bool _loading = false;
  String? _resultMessage;
  bool _success = false;

  Future<void> _wipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferma cancellazione'),
        content: const Text(
          'Questa azione eliminerà TUTTI gli utenti, gruppi, '
          'pronostici e immagini da Firestore e Storage.\n\n'
          'Gli account Firebase Auth NON verranno cancellati.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancella tutto'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _loading = true;
      _resultMessage = null;
    });

    try {
      final result = await _service.wipeData();
      final deleted = result['deleted'] as Map<String, dynamic>? ?? {};
      final total = deleted.values.fold<int>(
        0,
        (sum, v) => sum + (v is int ? v : 0),
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
        _resultMessage = 'Cancellati $total documenti/file.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _resultMessage = 'Errore: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wipe Data',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.red.shade700,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: _loading ? null : _wipe,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.delete_forever),
            label: Text(_loading ? 'Cancellazione...' : 'Cancella tutti i dati'),
          ),
        ),
        if (_resultMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _resultMessage!,
            style: TextStyle(
              color: _success ? Colors.green.shade700 : Colors.red.shade700,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}
