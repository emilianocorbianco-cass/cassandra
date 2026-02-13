import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app/cassandra_app.dart';
import 'app/state/app_state.dart';
import 'app/state/cassandra_scope.dart';
import 'services/auth/auth_service.dart';
import 'services/firestore/firestore_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Non facciamo crashare l'app se manca .env: lo segnaleremo nella pagina diagnostica.
  try {
    await dotenv.load(fileName: ".env");
  } catch (_) {}

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
    appState.setAuthService(authService);
    appState.setFirestoreService(firestoreService);
    // Ripristina profilo se sessione persistita
    final currentUser = authService.currentUser;
    if (currentUser != null) {
      appState.setProfileFromFirebaseUser(currentUser);
      // Merge profilo/gruppo Firestore (fire-and-forget, non blocca avvio)
      appState.hydrateProfileFromFirestore(currentUser.uid).catchError((_) {});
      // One-time migration: upload local data to Firestore
      appState.migrateLocalDataToFirestoreIfNeeded().catchError((_) {});
    }
  }

  runApp(CassandraScope(notifier: appState, child: const CassandraApp()));
}
