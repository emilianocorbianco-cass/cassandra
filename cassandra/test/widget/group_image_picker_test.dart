import 'package:cassandra/features/group/widgets/group_image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('GroupImageDisplay', () {
    testWidgets('shows default groups icon when no image is provided', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const GroupImageDisplay(imagePath: null)));

      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.byIcon(Icons.groups), findsOneWidget);
    });

    testWidgets('uses MemoryImage for data URI source', (tester) async {
      const pngBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg==';
      const source = 'data:image/png;base64,$pngBase64';

      await tester.pumpWidget(
        _wrap(const GroupImageDisplay(imagePath: source)),
      );

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isA<MemoryImage>());
      expect(find.byIcon(Icons.groups), findsNothing);
    });

    testWidgets('falls back to default icon for missing local file path', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const GroupImageDisplay(imagePath: '/tmp/does_not_exist.png')),
      );

      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.byIcon(Icons.groups), findsOneWidget);
    });
  });
}
