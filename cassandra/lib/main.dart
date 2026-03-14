import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/cassandra_app.dart';
import 'app/state/app_state.dart';
import 'app/state/cassandra_scope.dart';
import 'services/auth/auth_service.dart';
import 'services/firestore/firestore_service.dart';
import 'services/storage/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Color(0xFF344A54),
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Non facciamo crashare l'app se manca .env: lo segnaleremo nella pagina diagnostica.
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('dotenv load failed: $e');
  }

  // Firebase init (graceful: se manca config, auth disabilitato)
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase init failed (running without auth): $e');
  }

  final appState = await AppState.load();

  if (firebaseReady) {
    final authService = AuthService();
    final firestoreService = FirestoreService();
    final storageService = StorageService();
    appState.setFirestoreService(firestoreService);
    appState.setStorageService(storageService);
    appState.setAuthService(authService);
  }

  runApp(CassandraScope(notifier: appState, child: const CassandraApp()));
}
