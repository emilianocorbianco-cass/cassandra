import 'package:flutter/material.dart';

class ApiFootballDiagnosticsPage extends StatelessWidget {
  const ApiFootballDiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API-FOOTBALL diagnostica')),
      body: const Center(
        child: Text(
          'Pagina diagnostica API in arrivo (macro step 2).\n'
          'Qui testeremo la chiave e le chiamate fixtures.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
