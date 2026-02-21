import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/matchday/matchday_recovery_rules.dart';
import '../config/storage_keys.dart';

/// Stato della giornata di campionato, estratto da AppState per isolamento
/// e testabilità.
///
/// Gestisce: cursore giornata, progresso matchday (runtime),
/// finalizzazione giornate, auto-advance, origin kickoffs.
class MatchdayState extends ChangeNotifier {
  // ===== SharedPreferences keys =====
  static const _kCassandraMatchdayCursorV1 =
      StorageKeys.cassandraMatchdayCursorV1;
  static const int _kCassandraDefaultMatchdayCursor = 20;
  static const _kFinalizedMatchdaysV1 = StorageKeys.finalizedMatchdaysV1;
  static const _kCassandraMatchdayLastAutoBumpFromV1 =
      StorageKeys.cassandraMatchdayLastAutoBumpFromV1;
  static const _kOriginKickoffsByMatchIdV1 =
      StorageKeys.originKickoffsByMatchIdV1;

  final SharedPreferences? _prefs;

  MatchdayState._({required SharedPreferences? prefs}) : _prefs = prefs;

  /// Crea dallo storage persistente (usato da AppState.load).
  factory MatchdayState.fromPrefs(SharedPreferences? prefs) {
    return MatchdayState._(prefs: prefs);
  }

  /// In-memory (per i test).
  factory MatchdayState.inMemory() {
    return MatchdayState._(prefs: null);
  }

  // ======================================================================
  // MATCHDAY CURSOR
  // ======================================================================

  int? _cassandraMatchdayCursor;

  /// Giornata "corrente" secondo Cassandra (ignorando recuperi di round vecchi).
  /// Persistita in SharedPreferences.
  int get cassandraMatchdayCursor => _cassandraMatchdayCursor ??=
      (_prefs?.getInt(_kCassandraMatchdayCursorV1) ??
      _kCassandraDefaultMatchdayCursor);

  Future<void> setCassandraMatchdayCursor(int dayNumber) async {
    if (dayNumber <= 0) return;
    _cassandraMatchdayCursor = dayNumber;
    await _prefs?.setInt(_kCassandraMatchdayCursorV1, dayNumber);

    _uiMatchdayNumber = null;
    notifyListeners();
  }

  Future<void> bumpCassandraMatchdayCursor() async {
    await setCassandraMatchdayCursor(cassandraMatchdayCursor + 1);
  }

  // ======================================================================
  // MATCHDAY FINALIZATION
  // ======================================================================

  bool _finalizedMatchdaysLoaded = false;
  final Set<int> _finalizedMatchdays = <int>{};

  void ensureFinalizedMatchdaysLoaded() {
    if (_finalizedMatchdaysLoaded) return;
    _finalizedMatchdaysLoaded = true;

    final raw = _prefs?.getString(_kFinalizedMatchdaysV1);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final e in decoded) {
          final n = int.tryParse(e.toString());
          if (n != null && n > 0) _finalizedMatchdays.add(n);
        }
      }
    } catch (_) {
      // ignore corrupt storage
    }
  }

  bool isMatchdayFinalized(int matchdayNumber) {
    ensureFinalizedMatchdaysLoaded();
    return _finalizedMatchdays.contains(matchdayNumber);
  }

  Future<bool> markMatchdayFinalized(int matchdayNumber) async {
    if (matchdayNumber <= 0) return false;
    ensureFinalizedMatchdaysLoaded();
    if (_finalizedMatchdays.contains(matchdayNumber)) return false;

    _finalizedMatchdays.add(matchdayNumber);
    final list = _finalizedMatchdays.toList()..sort();
    await _prefs?.setString(_kFinalizedMatchdaysV1, jsonEncode(list));
    notifyListeners();
    return true;
  }

  // ======================================================================
  // AUTO-BUMP
  // ======================================================================

  int? get lastAutoBumpFromMatchday =>
      _prefs?.getInt(_kCassandraMatchdayLastAutoBumpFromV1);

  Future<bool> maybeAutoBumpCassandraMatchdayCursor({
    required int fromMatchday,
  }) async {
    final prefs = _prefs;
    if (prefs == null) return false;

    final last = prefs.getInt(_kCassandraMatchdayLastAutoBumpFromV1) ?? -1;
    if (last == fromMatchday) return false;

    await prefs.setInt(_kCassandraMatchdayLastAutoBumpFromV1, fromMatchday);
    await setCassandraMatchdayCursor(fromMatchday + 1);
    return true;
  }

  // ======================================================================
  // ORIGIN KICKOFFS
  // ======================================================================

  bool _originKickoffsLoaded = false;
  Map<String, String> _originKickoffIsoByMatchId = {};

  void ensureOriginKickoffsLoaded() {
    if (_originKickoffsLoaded) return;
    _originKickoffsLoaded = true;
    final raw = _prefs?.getString(_kOriginKickoffsByMatchIdV1);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _originKickoffIsoByMatchId = {
          for (final e in decoded.entries) e.key.toString(): e.value.toString(),
        };
      }
    } catch (_) {
      // ignore: keep empty
    }
  }

  void registerOriginKickoff({
    required String matchId,
    required DateTime kickoff,
  }) {
    ensureOriginKickoffsLoaded();
    _originKickoffIsoByMatchId.putIfAbsent(
      matchId,
      () => kickoff.toUtc().toIso8601String(),
    );
  }

  DateTime originKickoffFor({
    required String matchId,
    required DateTime fallbackKickoff,
  }) {
    ensureOriginKickoffsLoaded();
    final iso = _originKickoffIsoByMatchId[matchId];
    if (iso == null) return fallbackKickoff;
    final parsed = DateTime.tryParse(iso);
    return parsed?.toLocal() ?? fallbackKickoff;
  }

  Future<void> persistOriginKickoffs() async {
    final prefs = _prefs;
    if (prefs == null) return;
    ensureOriginKickoffsLoaded();
    await prefs.setString(
      _kOriginKickoffsByMatchIdV1,
      jsonEncode(_originKickoffIsoByMatchId),
    );
  }

  // ======================================================================
  // MATCHDAY PROGRESS (runtime, non persistito)
  // ======================================================================

  final Map<int, MatchdayProgress> _matchdayProgressByDay = {};

  int? _uiMatchdayNumber;
  int? _autoAdvancedFromMatchday;
  int? _autoFinalizedFromMatchday;

  int get uiMatchdayNumber => _uiMatchdayNumber ?? cassandraMatchdayCursor;

  void setUiMatchdayNumber(int? matchdayNumber) {
    _uiMatchdayNumber = matchdayNumber;
    notifyListeners();
  }

  MatchdayProgress? matchdayProgressFor(int matchdayNumber) =>
      _matchdayProgressByDay[matchdayNumber];

  Future<void> _runAutoActionWithRetry({
    required String label,
    required Future<void> Function() action,
    required void Function() onPermanentFailure,
    int attempts = 3,
  }) async {
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        await action();
        return;
      } catch (error, stackTrace) {
        final isLastAttempt = attempt >= attempts;
        debugPrint(
          '[matchday] $label attempt $attempt/$attempts failed: $error\n$stackTrace',
        );
        if (isLastAttempt) {
          onPermanentFailure();
          return;
        }
        final backoff = Duration(milliseconds: 250 * (1 << (attempt - 1)));
        await Future<void>.delayed(backoff);
      }
    }
  }

  void setMatchdayProgress({
    required int matchdayNumber,
    required MatchdayProgress progress,
    bool allowAutoAdvance = true,
  }) {
    _matchdayProgressByDay[matchdayNumber] = progress;

    _uiMatchdayNumber = matchdayNumber;

    // AUTO-ADVANCE: primaryDone
    if (allowAutoAdvance &&
        progress.primaryDone &&
        progress.isValidMatchday &&
        matchdayNumber == cassandraMatchdayCursor &&
        _autoAdvancedFromMatchday != matchdayNumber) {
      _autoAdvancedFromMatchday = matchdayNumber;
      Future.microtask(() async {
        await _runAutoActionWithRetry(
          label: 'auto-advance($matchdayNumber)',
          action: () => setCassandraMatchdayCursor(matchdayNumber + 1),
          onPermanentFailure: () => _autoAdvancedFromMatchday = null,
        );
      });
    }

    // AUTO-FINALIZE: finalDone
    if (progress.finalDone &&
        progress.isValidMatchday &&
        _autoFinalizedFromMatchday != matchdayNumber) {
      _autoFinalizedFromMatchday = matchdayNumber;
      Future.microtask(() async {
        await _runAutoActionWithRetry(
          label: 'auto-finalize($matchdayNumber)',
          action: () => markMatchdayFinalized(matchdayNumber),
          onPermanentFailure: () => _autoFinalizedFromMatchday = null,
        );
      });
    }

    notifyListeners();
  }

  void clearMatchdayProgress(int matchdayNumber) {
    if (_matchdayProgressByDay.remove(matchdayNumber) != null) {
      if (_uiMatchdayNumber == matchdayNumber) _uiMatchdayNumber = null;
      notifyListeners();
    }
  }
}
