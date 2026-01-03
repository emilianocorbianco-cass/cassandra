import 'package:flutter/material.dart';

import 'app/cassandra_app.dart';
import 'app/state/app_state.dart';
import 'app/state/cassandra_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final appState = await AppState.load();

  runApp(CassandraScope(notifier: appState, child: const CassandraApp()));
}
