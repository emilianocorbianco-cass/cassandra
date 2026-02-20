import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:cassandra/app/state/app_settings.dart';

void main() {
  // ==========================================================================
  // CassandraLanguage round-trip serialization
  // ==========================================================================
  group('CassandraLanguage serialization', () {
    test('round-trip for all values', () {
      for (final lang in CassandraLanguage.values) {
        final stored = cassandraLanguageToStorage(lang);
        final restored = cassandraLanguageFromStorage(stored);
        expect(restored, lang, reason: 'round-trip failed for $lang');
      }
    });

    test('fromStorage defaults to system for null', () {
      expect(cassandraLanguageFromStorage(null), CassandraLanguage.system);
    });

    test('fromStorage defaults to system for unknown string', () {
      expect(cassandraLanguageFromStorage('fr'), CassandraLanguage.system);
      expect(cassandraLanguageFromStorage(''), CassandraLanguage.system);
    });

    test('toStorage returns expected strings', () {
      expect(cassandraLanguageToStorage(CassandraLanguage.system), 'system');
      expect(cassandraLanguageToStorage(CassandraLanguage.it), 'it');
      expect(cassandraLanguageToStorage(CassandraLanguage.en), 'en');
    });
  });

  // ==========================================================================
  // PredictionVisibility round-trip serialization
  // ==========================================================================
  group('PredictionVisibility serialization', () {
    test('round-trip for all values', () {
      for (final vis in PredictionVisibility.values) {
        final stored = predictionVisibilityToStorage(vis);
        final restored = predictionVisibilityFromStorage(stored);
        expect(restored, vis, reason: 'round-trip failed for $vis');
      }
    });

    test('fromStorage defaults to friends for null', () {
      expect(
        predictionVisibilityFromStorage(null),
        PredictionVisibility.friends,
      );
    });

    test('fromStorage defaults to friends for unknown string', () {
      expect(
        predictionVisibilityFromStorage('unknown'),
        PredictionVisibility.friends,
      );
      expect(predictionVisibilityFromStorage(''), PredictionVisibility.friends);
    });

    test('toStorage returns expected strings', () {
      expect(
        predictionVisibilityToStorage(PredictionVisibility.public),
        'public',
      );
      expect(
        predictionVisibilityToStorage(PredictionVisibility.friends),
        'friends',
      );
      expect(
        predictionVisibilityToStorage(PredictionVisibility.private),
        'private',
      );
    });
  });

  // ==========================================================================
  // localeForLanguage
  // ==========================================================================
  group('localeForLanguage', () {
    test('system returns null (follow device)', () {
      expect(localeForLanguage(CassandraLanguage.system), isNull);
    });

    test('it returns Locale("it")', () {
      expect(localeForLanguage(CassandraLanguage.it), const Locale('it'));
    });

    test('en returns Locale("en")', () {
      expect(localeForLanguage(CassandraLanguage.en), const Locale('en'));
    });
  });

  // ==========================================================================
  // predictionVisibilityLabel
  // ==========================================================================
  group('predictionVisibilityLabel', () {
    test('italian labels', () {
      expect(
        predictionVisibilityLabel(PredictionVisibility.public, english: false),
        'Pubblico',
      );
      expect(
        predictionVisibilityLabel(PredictionVisibility.friends, english: false),
        'Amici',
      );
      expect(
        predictionVisibilityLabel(PredictionVisibility.private, english: false),
        'Privato',
      );
    });

    test('english labels', () {
      expect(
        predictionVisibilityLabel(PredictionVisibility.public, english: true),
        'Public',
      );
      expect(
        predictionVisibilityLabel(PredictionVisibility.friends, english: true),
        'Friends',
      );
      expect(
        predictionVisibilityLabel(PredictionVisibility.private, english: true),
        'Private',
      );
    });
  });
}
