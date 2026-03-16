import 'package:cloud_functions/cloud_functions.dart';

class ColdTestService {
  final FirebaseFunctions _functions;

  ColdTestService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'europe-west1');

  Future<Map<String, dynamic>> wipeData() async {
    final callable = _functions.httpsCallable(
      'coldTestWipeData',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );
    final result = await callable.call<Map<String, dynamic>>();
    return result.data;
  }

  Future<Map<String, dynamic>> seedMatchday({
    required int dayNumber,
    int kickoffIntervalMin = 10,
    int matchDurationMin = 12,
  }) async {
    final callable = _functions.httpsCallable(
      'coldTestSeedMatchday',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
    );
    final result = await callable.call<Map<String, dynamic>>({
      'dayNumber': dayNumber,
      'kickoffIntervalMin': kickoffIntervalMin,
      'matchDurationMin': matchDurationMin,
    });
    return result.data;
  }

  Future<Map<String, dynamic>> resolveMatches({
    required int dayNumber,
  }) async {
    final callable = _functions.httpsCallable(
      'coldTestResolveMatches',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
    );
    final result = await callable.call<Map<String, dynamic>>({
      'dayNumber': dayNumber,
    });
    return result.data;
  }
}
