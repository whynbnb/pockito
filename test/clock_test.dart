import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pockito/main.dart';

void main() {
  group('clock helpers', () {
    test('formats 24-hour and 12-hour digits', () {
      final midnight = DateTime(2026, 1, 2, 0, 5, 9);
      expect(clockDigitsFor(midnight, use24Hour: true), (
        hour: '00',
        minute: '05',
        second: '09',
        period: '',
      ));
      expect(clockDigitsFor(midnight, use24Hour: false), (
        hour: '12',
        minute: '05',
        second: '09',
        period: 'AM',
      ));

      final afternoon = DateTime(2026, 1, 2, 13, 7, 3);
      expect(clockDigitsFor(afternoon, use24Hour: true), (
        hour: '13',
        minute: '07',
        second: '03',
        period: '',
      ));
      expect(clockDigitsFor(afternoon, use24Hour: false), (
        hour: '01',
        minute: '07',
        second: '03',
        period: 'PM',
      ));

      final noon = DateTime(2026, 1, 2, 12, 0, 0);
      expect(clockDigitsFor(noon, use24Hour: false), (
        hour: '12',
        minute: '00',
        second: '00',
        period: 'PM',
      ));
    });

    test('splits the time into binary coded decimal columns', () {
      final evening = DateTime(2026, 1, 2, 23, 59, 58);
      expect(clockBinaryDigits(evening, use24Hour: true), [2, 3, 5, 9, 5, 8]);
      expect(
        clockBinaryDigits(DateTime(2026, 1, 2, 9, 5, 7), use24Hour: true),
        [0, 9, 0, 5, 0, 7],
      );
      final noon = DateTime(2026, 1, 2, 12, 0, 0);
      expect(clockBinaryDigits(noon, use24Hour: false).first, 1);
    });

    test('reads individual binary weights', () {
      expect(clockBinaryBit(7, 4), isTrue);
      expect(clockBinaryBit(7, 8), isFalse);
      expect(clockBinaryBit(7, 1), isTrue);
      expect(clockBinaryBit(0, 1), isFalse);
      expect(clockBinaryBit(9, 8), isTrue);
      expect(clockBinaryBit(9, 1), isTrue);
    });
  });

  testWidgets('opens the clock from the tool list', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Clock'), 200.0);
    await tester.ensureVisible(find.text('Clock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clock'));
    await tester.pumpAndSettle();

    expect(find.byType(ClockScreen), findsOneWidget);
    expect(find.text('Analog'), findsOneWidget);
    expect(find.byKey(const ValueKey('clock-fullscreen')), findsOneWidget);
    expect(find.byKey(const ValueKey('clock-wakelock')), findsOneWidget);
  });

  testWidgets('swipes through all four clock faces', (tester) async {
    await tester.pumpWidget(const VaultApp(home: ClockScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Analog'), findsOneWidget);
    for (final face in const ['Flip', 'Binary', 'Big digits']) {
      await tester.drag(
        find.byKey(const ValueKey('clock-pages')),
        const Offset(-700, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text(face), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('clock-dot-0')));
    await tester.pumpAndSettle();
    expect(find.text('Analog'), findsOneWidget);
  });

  testWidgets('enters and exits fullscreen', (tester) async {
    await tester.pumpWidget(const VaultApp(home: ClockScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-fullscreen')));
    await tester.pumpAndSettle();

    expect(find.text('Clock'), findsNothing);
    expect(find.byKey(const ValueKey('clock-exit-fullscreen')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('clock-wakelock-overlay')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('clock-exit-fullscreen')));
    await tester.pumpAndSettle();

    expect(find.text('Clock'), findsOneWidget);
    expect(find.byKey(const ValueKey('clock-fullscreen')), findsOneWidget);
  });

  testWidgets('exits fullscreen with Escape', (tester) async {
    await tester.pumpWidget(const VaultApp(home: ClockScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('clock-exit-fullscreen')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Clock'), findsOneWidget);
    expect(find.byKey(const ValueKey('clock-fullscreen')), findsOneWidget);
  });

  testWidgets('lays out every face in portrait and landscape', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final size in const [Size(390, 844), Size(844, 390)]) {
      tester.view.physicalSize = size;
      for (final face in ClockFace.values) {
        await tester.pumpWidget(
          VaultApp(
            home: ClockScreen(key: ValueKey(face), initialFace: face),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(face.englishName), findsOneWidget);
      }
    }
  });
}
