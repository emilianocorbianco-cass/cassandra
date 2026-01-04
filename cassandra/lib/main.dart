import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/cassandra_app.dart';
import 'app/state/app_state.dart';
import 'app/state/cassandra_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Non facciamo crashare l'app se manca .env: lo segnaleremo nella pagina diagnostica.
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {}

  final appState = await AppState.load();

  runApp(CassandraScope(notifier: appState, child: const CassandraApp()));
}
