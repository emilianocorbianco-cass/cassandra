import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../app/state/app_state.dart';

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialized = false;
  AppState? _boundAppState;

  Future<void> initializeForAppState(AppState appState) async {
    _boundAppState = appState;

    if (!_initialized) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) {
        final app = _boundAppState;
        if (app == null) return;
        unawaited(app.setDevicePushToken(token));
      });

      _initialized = true;
    }

    final current = await _messaging.getNotificationSettings();
    final status = current.authorizationStatus;
    if (status == AuthorizationStatus.notDetermined) {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    }

    final refreshed = await _messaging.getNotificationSettings();
    if (refreshed.authorizationStatus == AuthorizationStatus.denied) return;
    if (refreshed.authorizationStatus == AuthorizationStatus.notDetermined) {
      return;
    }

    try {
      final token = await _messaging.getToken();
      if (token == null || token.trim().isEmpty) return;
      await appState.setDevicePushToken(token);
    } catch (_) {
      // ignore: token sync is best effort
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _initialized = false;
    _boundAppState = null;
  }
}
