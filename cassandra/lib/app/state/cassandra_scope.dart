import 'package:flutter/widgets.dart';
import 'app_state.dart';

class CassandraScope extends InheritedNotifier<AppState> {
  const CassandraScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CassandraScope>();
    assert(
      scope != null,
      'CassandraScope non trovato. Hai wrappato CassandraApp con CassandraScope in main.dart?',
    );
    return scope!.notifier!;
  }
}
