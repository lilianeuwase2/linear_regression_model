import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maize_yield_app/main.dart';

/// Scrolls to the Predict button (the page is long) and taps it.
Future<void> tapPredict(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Predict'));
  await tester.tap(find.text('Predict'));
  await tester.pump();
}

void main() {
  testWidgets('Page has 10 text fields, a Predict button and a display area', (tester) async {
    await tester.pumpWidget(const MaizeYieldApp());

    expect(find.byType(TextField), findsNWidgets(10));
    expect(find.text('Predict'), findsOneWidget);
    expect(find.text('Your prediction will appear here.'), findsOneWidget);
  });

  testWidgets('Empty fields show a readable error in the display area', (tester) async {
    await tester.pumpWidget(const MaizeYieldApp());

    await tapPredict(tester);

    expect(find.textContaining('Season rainfall (mm) is missing.'), findsOneWidget);
  });

  testWidgets('Text in a number field shows a wrong-type error', (tester) async {
    await tester.pumpWidget(const MaizeYieldApp());

    await tester.enterText(find.widgetWithText(TextField, 'Season rainfall (mm)'), 'abc');
    await tapPredict(tester);

    expect(find.textContaining('must be a number'), findsOneWidget);
  });
}
