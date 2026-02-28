import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../app/state/app_state.dart';

class PushNotificationsService {
  PushNotificationsService._();

  static final PushNotificationsService instance = PushNotificationsService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenRefreshSub;
  bool _initialized = false;
  AppState? _boundAppState;

  Future<String?> _resolveFcmTokenWithRetry() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final token = await _messaging.getToken();
        if (token != null && token.trim().isNotEmpty) {
          return token.trim();
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[push] getToken attempt ${attempt + 1} failed: $e');
          debugPrint('$st');
        }
      }

      try {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken != null && apnsToken.trim().isNotEmpty) {
          final token = await _messaging.getToken();
          if (token != null && token.trim().isNotEmpty) {
            return token.trim();
          }
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[push] getAPNSToken attempt ${attempt + 1} failed: $e');
          debugPrint('$st');
        }
      }

      if (attempt < 5) {
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    return null;
  }

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
      final token = await _resolveFcmTokenWithRetry();
      if (token == null || token.trim().isEmpty) return;
      await appState.setDevicePushToken(token);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[push] token sync failed: $e');
        debugPrint('$st');
      }
    }
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
    _initialized = false;
    _boundAppState = null;
  }
}
