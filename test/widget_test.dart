import 'package:flutter_test/flutter_test.dart';

import 'package:macrotrack/main.dart';

void main() {
  testWidgets('app boots to home shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MacroTrackApp());
    expect(find.byType(MacroTrackApp), findsOneWidget);
  });
}
