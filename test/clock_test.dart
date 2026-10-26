import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pockito/main.dart';

class _MemoryPreferences extends LocalPreferences {
  _MemoryPreferences(this.values);

  final Map<String, String> values;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

LocalPreferences clockPreferences() {
  final directory = Directory.systemTemp.createTempSync('pockito_clock_test');
  addTearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } catch (_) {}
  });
  return LocalPreferences.forFile('clock.json', directory);
}

Widget clockApp({
  ClockFace face = ClockFace.analog,
  Key? key,
  LocalPreferences? preferences,
}) => VaultApp(
  home: ClockScreen(
    key: key,
    initialFace: face,
    preferences: preferences ?? clockPreferences(),
  ),
);

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

    test('segment masks describe the eight-segment digits', () {
      expect(segmentDigitMasks, hasLength(10));
      expect(segmentDigitMasks[0], 63);
      expect(segmentDigitMasks[1], 6);
      expect(segmentDigitMasks[2], 91);
      expect(segmentDigitMasks[8], 127);
      expect(segmentDigitMasks[9], 111);
    });
  });

  test('clock settings round-trip and clamp invalid values', () {
    final settings = ClockSettings()
      ..loop = true
      ..layout = ClockLayout.landscape
      ..use24Hour = false
      ..analogScale = 0.85
      ..analogShowDigital = false
      ..analogShowDate = false
      ..analogShowMinuteHand = false
      ..analogShowSecondHand = false
      ..flipScale = 1.15
      ..flipShowSeconds = false
      ..flipShowDate = false
      ..binaryScale = 0.75
      ..binaryShowSeconds = false
      ..binaryShowLabels = false
      ..binaryShowDigital = false
      ..binaryShowDate = false
      ..bigShowDate = false
      ..bigShowSeconds = false
      ..segmentScale = 1.1
      ..segmentShowSeconds = false
      ..segmentShowDate = false
      ..segmentColor = segmentColorOptions[2].toARGB32()
      ..segmentShowBorder = false
      ..segmentBorderWidth = 2.5
      ..segmentPadding = 32
      ..segmentMargin = 16;
    final restored = ClockSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );
    expect(restored.toJson(), settings.toJson());

    final clamped = ClockSettings.fromJson({
      'analogScale': 99,
      'flipScale': 0.1,
      'bigDate': 'not a bool',
      'segmentScale': 5,
      'segmentBorderWidth': 99,
      'segmentColor': -1,
      'segmentPadding': 100,
      'segmentMargin': -5,
      'layout': 'diagonal',
    });
    expect(clamped.analogScale, 1.2);
    expect(clamped.flipScale, 0.7);
    expect(clamped.bigShowDate, isTrue);
    expect(clamped.segmentScale, 1.2);
    expect(clamped.segmentBorderWidth, 3);
    expect(clamped.segmentColor, defaultSegmentColor);
    expect(clamped.segmentPadding, 48);
    expect(clamped.segmentMargin, 0);
    expect(clamped.layout, ClockLayout.auto);
  });

  test('clock settings reset sections independently', () {
    final settings = ClockSettings()
      ..loop = true
      ..layout = ClockLayout.portrait
      ..use24Hour = true
      ..analogScale = 1.2
      ..analogShowDigital = false
      ..analogShowDate = false
      ..analogShowMinuteHand = false
      ..analogShowSecondHand = false
      ..flipScale = 0.7
      ..flipShowSeconds = false
      ..flipShowDate = false
      ..binaryScale = 0.7
      ..binaryShowSeconds = false
      ..binaryShowLabels = false
      ..binaryShowDigital = false
      ..binaryShowDate = false
      ..bigShowDate = false
      ..bigShowSeconds = false
      ..segmentScale = 0.7
      ..segmentShowSeconds = false
      ..segmentShowDate = false
      ..segmentColor = segmentColorOptions[3].toARGB32()
      ..segmentShowBorder = false
      ..segmentBorderWidth = 3
      ..segmentPadding = 36
      ..segmentMargin = 24;

    settings.resetAnalog();
    expect(settings.analogScale, 1);
    expect(settings.analogShowDigital, isTrue);
    expect(settings.analogShowMinuteHand, isTrue);
    expect(settings.flipScale, 0.7);
    expect(settings.binaryShowSeconds, isFalse);

    settings.resetFlip();
    expect(settings.flipScale, 1);
    expect(settings.flipShowSeconds, isTrue);
    expect(settings.binaryShowSeconds, isFalse);

    settings.resetBinary();
    expect(settings.binaryScale, 1);
    expect(settings.binaryShowSeconds, isTrue);
    expect(settings.binaryShowLabels, isTrue);
    expect(settings.bigShowDate, isFalse);

    settings.resetBig();
    expect(settings.bigShowDate, isTrue);
    expect(settings.bigShowSeconds, isTrue);
    expect(settings.segmentScale, 0.7);

    settings.resetSegment();
    expect(settings.segmentScale, 1);
    expect(settings.segmentShowSeconds, isTrue);
    expect(settings.segmentShowDate, isTrue);
    expect(settings.segmentColor, defaultSegmentColor);
    expect(settings.segmentShowBorder, isTrue);
    expect(settings.segmentBorderWidth, 1);
    expect(settings.segmentPadding, 20);
    expect(settings.segmentMargin, 0);

    settings.segmentShowDate = false;
    settings.segmentShowSeconds = false;

    settings.loop = true;
    settings.layout = ClockLayout.landscape;
    settings.use24Hour = true;
    settings.analogShowDate = false;
    settings.resetAll();
    expect(settings.loop, isFalse);
    expect(settings.layout, ClockLayout.auto);
    expect(settings.use24Hour, isNull);
    expect(settings.analogShowDate, isTrue);
    expect(settings.segmentShowDate, isTrue);
    expect(settings.segmentShowSeconds, isTrue);
  });

  test('clock settings persist in a local preferences file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pockito_clock_store',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final preferences = LocalPreferences.forFile('clock.json', directory);
    final settings = ClockSettings()
      ..loop = true
      ..binaryShowSeconds = false;
    await preferences.setString('settings', jsonEncode(settings.toJson()));

    final raw = await LocalPreferences.forFile(
      'clock.json',
      directory,
    ).getString('settings');
    expect(raw, isNotNull);
    final restored = ClockSettings.fromJson(
      jsonDecode(raw!) as Map<String, dynamic>,
    );
    expect(restored.loop, isTrue);
    expect(restored.binaryShowSeconds, isFalse);
    expect(File('${directory.path}/clock.json').existsSync(), isTrue);
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

  testWidgets('swipes through all five clock faces', (tester) async {
    await tester.pumpWidget(clockApp());
    await tester.pumpAndSettle();

    expect(find.text('Analog'), findsOneWidget);
    for (final face in const ['Flip', 'Binary', 'Big digits', '8-segment']) {
      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pumpAndSettle();
      expect(find.text(face), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('clock-dot-0')));
    await tester.pumpAndSettle();
    expect(find.text('Analog'), findsOneWidget);
  });

  testWidgets('enters and exits fullscreen', (tester) async {
    await tester.pumpWidget(clockApp());
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
    await tester.pumpWidget(clockApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-fullscreen')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('clock-exit-fullscreen')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Clock'), findsOneWidget);
    expect(find.byKey(const ValueKey('clock-fullscreen')), findsOneWidget);
  });

  testWidgets('hides the analog digital clock from settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('analog-digital')), findsOneWidget);
    expect(find.byKey(const ValueKey('analog-date')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Clock settings'), findsOneWidget);

    final digital = find.byKey(const ValueKey('clock-analog-digital'));
    expect(tester.widget<SwitchListTile>(digital).value, isTrue);
    await tester.tap(digital);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(digital).value, isFalse);

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('analog-digital')), findsNothing);
    expect(find.byKey(const ValueKey('analog-date')), findsOneWidget);
  });

  testWidgets('switches hour format and enables looping', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('24-hour'));
    await tester.pump();
    final segmented = tester.widget<SegmentedButton<bool>>(
      find.byKey(const ValueKey('clock-hour-format')),
    );
    expect(segmented.selected, {true});

    final loop = find.byKey(const ValueKey('clock-loop'));
    await tester.tap(loop);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(loop).value, isTrue);

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    final digital = tester.widget<Text>(
      find.byKey(const ValueKey('analog-digital')),
    );
    expect(digital.data, isNot(contains('AM')));
    expect(digital.data, isNot(contains('PM')));

    await tester.drag(find.byType(PageView), const Offset(700, 0));
    await tester.pumpAndSettle();
    expect(find.text('8-segment'), findsOneWidget);
  });

  testWidgets('hides flip seconds and calendar date from settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.flip));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flip-seconds')), findsOneWidget);
    expect(find.byKey(const ValueKey('flip-date')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final seconds = find.byKey(const ValueKey('clock-flip-seconds'));
    await tester.ensureVisible(seconds);
    await tester.pump();
    await tester.tap(seconds);
    await tester.pump();

    final date = find.byKey(const ValueKey('clock-flip-date'));
    await tester.ensureVisible(date);
    await tester.pump();
    await tester.tap(date);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('flip-seconds')), findsNothing);
    expect(find.byKey(const ValueKey('flip-date')), findsNothing);
  });

  testWidgets('hides binary labels, digital time and date from settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.binary));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('binary-label-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('binary-legend')), findsOneWidget);
    expect(find.byKey(const ValueKey('binary-digital')), findsOneWidget);
    expect(find.byKey(const ValueKey('binary-date')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    for (final key in const [
      'clock-binary-labels',
      'clock-binary-digital',
      'clock-binary-date',
    ]) {
      final toggle = find.byKey(ValueKey(key));
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();
    }

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('binary-label-title')), findsNothing);
    expect(find.byKey(const ValueKey('binary-legend')), findsNothing);
    expect(find.byKey(const ValueKey('binary-label-0')), findsNothing);
    expect(find.byKey(const ValueKey('binary-digital')), findsNothing);
    expect(find.byKey(const ValueKey('binary-date')), findsNothing);
  });

  testWidgets('hides big-digit date and seconds from settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.big));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('big-date')), findsOneWidget);
    expect(find.byKey(const ValueKey('big-seconds')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    for (final key in const ['clock-big-date', 'clock-big-seconds']) {
      final toggle = find.byKey(ValueKey(key));
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();
    }

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('big-date')), findsNothing);
    expect(find.byKey(const ValueKey('big-seconds')), findsNothing);
  });

  testWidgets('scales the analog face from settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp());
    await tester.pumpAndSettle();

    final before = tester.getSize(find.byKey(const ValueKey('analog-face')));

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final slider = find.byKey(const ValueKey('clock-analog-scale'));
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(-80, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    final after = tester.getSize(find.byKey(const ValueKey('analog-face')));
    expect(after.width, lessThan(before.width));
  });

  testWidgets('scales the flip cards from settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.flip));
    await tester.pumpAndSettle();

    final cards = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_FlipCard',
    );
    final before = tester.getSize(cards.first);

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final slider = find.byKey(const ValueKey('clock-flip-scale'));
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(-80, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    final after = tester.getSize(cards.first);
    expect(after.width, lessThan(before.width));
  });

  testWidgets('scales the binary matrix from settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.binary));
    await tester.pumpAndSettle();

    final before = tester.getSize(find.byKey(const ValueKey('binary-matrix')));

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final slider = find.byKey(const ValueKey('clock-binary-scale'));
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(-80, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    final after = tester.getSize(find.byKey(const ValueKey('binary-matrix')));
    expect(after.width, lessThan(before.width));
  });

  testWidgets('hides binary seconds from settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.binary));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('binary-seconds')), findsOneWidget);
    final before = tester.widget<Text>(
      find.byKey(const ValueKey('binary-digital')),
    );
    expect(':'.allMatches(before.data!).length, 2);

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final seconds = find.byKey(const ValueKey('clock-binary-seconds'));
    await tester.ensureVisible(seconds);
    await tester.pump();
    await tester.tap(seconds);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('binary-seconds')), findsNothing);
    final after = tester.widget<Text>(
      find.byKey(const ValueKey('binary-digital')),
    );
    expect(':'.allMatches(after.data!).length, 1);
  });

  testWidgets('hides analog minute and second hands from settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('analog-hands-11')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    for (final key in const [
      'clock-analog-minute-hand',
      'clock-analog-second-hand',
    ]) {
      final toggle = find.byKey(ValueKey(key));
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pump();
    }

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('analog-hands-00')), findsOneWidget);
  });

  testWidgets('persists clock settings across screens', (tester) async {
    final store = <String, String>{};
    final first = _MemoryPreferences(store);
    final second = _MemoryPreferences(store);

    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(preferences: first));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clock-analog-digital')));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('analog-digital')), findsNothing);
    expect(store['settings'], isNotNull);

    await tester.pumpWidget(
      clockApp(key: const ValueKey('reloaded'), preferences: second),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('analog-digital')), findsNothing);
  });

  testWidgets('resets all clock settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-loop')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('clock-analog-digital')));
    await tester.pump();

    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('clock-loop')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('clock-analog-digital')),
          )
          .value,
      isFalse,
    );

    await tester.tap(find.byKey(const ValueKey('clock-reset-all')));
    await tester.pump();

    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('clock-loop')))
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('clock-analog-digital')),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('analog-digital')), findsOneWidget);
  });

  testWidgets('resets one clock section without touching others', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.flip));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-analog-digital')));
    await tester.pump();

    final flipDate = find.byKey(const ValueKey('clock-flip-date'));
    await tester.ensureVisible(flipDate);
    await tester.pump();
    await tester.tap(flipDate);
    await tester.pump();

    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('clock-flip-date')))
          .value,
      isFalse,
    );

    final resetAnalog = find.byKey(const ValueKey('clock-reset-analog'));
    await tester.ensureVisible(resetAnalog);
    await tester.pump();
    await tester.tap(resetAnalog);
    await tester.pump();

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('clock-analog-digital')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('clock-flip-date')))
          .value,
      isFalse,
    );

    final resetFlip = find.byKey(const ValueKey('clock-reset-flip'));
    await tester.ensureVisible(resetFlip);
    await tester.pump();
    await tester.tap(resetFlip);
    await tester.pump();

    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('clock-flip-date')))
          .value,
      isTrue,
    );
  });

  testWidgets('shows and configures the 8-segment clock', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.segment));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('segment-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('segment-seconds')), findsOneWidget);
    expect(find.byKey(const ValueKey('segment-date')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final seconds = find.byKey(const ValueKey('clock-segment-seconds'));
    await tester.ensureVisible(seconds);
    await tester.pump();
    await tester.tap(seconds);
    await tester.pump();

    final date = find.byKey(const ValueKey('clock-segment-date'));
    await tester.ensureVisible(date);
    await tester.pump();
    await tester.tap(date);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('segment-seconds')), findsNothing);
    expect(find.byKey(const ValueKey('segment-date')), findsNothing);
  });

  testWidgets('scales the 8-segment display from settings', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.segment));
    await tester.pumpAndSettle();

    final before = tester.getSize(find.byKey(const ValueKey('segment-panel')));

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final slider = find.byKey(const ValueKey('clock-segment-scale'));
    await tester.ensureVisible(slider);
    await tester.drag(slider, const Offset(-80, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    final after = tester.getSize(find.byKey(const ValueKey('segment-panel')));
    expect(after.width, lessThan(before.width));
  });

  testWidgets('changes the 8-segment color', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.segment));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final swatch = find.byKey(const ValueKey('clock-segment-color-2'));
    await tester.ensureVisible(swatch);
    await tester.pump();
    await tester.tap(swatch);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    final panel = tester.widget<Container>(
      find.byKey(const ValueKey('segment-panel')),
    );
    final decoration = panel.decoration! as BoxDecoration;
    final border = decoration.border! as Border;
    expect(border.top.color, segmentColorOptions[2].withValues(alpha: 0.28));
    expect(border.top.width, 1);
  });

  testWidgets('controls the 8-segment border', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.segment));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('clock-segment-border'));
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.tap(toggle);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    var panel = tester.widget<Container>(
      find.byKey(const ValueKey('segment-panel')),
    );
    expect((panel.decoration! as BoxDecoration).border, isNull);

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final toggleAgain = find.byKey(const ValueKey('clock-segment-border'));
    await tester.ensureVisible(toggleAgain);
    await tester.pump();
    await tester.tap(toggleAgain);
    await tester.pump();

    final widthSlider = find.byKey(
      const ValueKey('clock-segment-border-width'),
    );
    await tester.ensureVisible(widthSlider);
    await tester.pump();
    await tester.drag(widthSlider, const Offset(80, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    panel = tester.widget<Container>(
      find.byKey(const ValueKey('segment-panel')),
    );
    final border = (panel.decoration! as BoxDecoration).border! as Border;
    expect(border.top.width, greaterThan(1));
    expect(
      border.top.color,
      const Color(defaultSegmentColor).withValues(alpha: 0.28),
    );
  });

  testWidgets('adjusts the 8-segment padding and margin', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(clockApp(face: ClockFace.segment));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final padding = find.byKey(const ValueKey('clock-segment-padding'));
    await tester.ensureVisible(padding);
    await tester.pump();
    await tester.drag(padding, const Offset(80, 0));
    await tester.pumpAndSettle();

    final margin = find.byKey(const ValueKey('clock-segment-margin'));
    await tester.ensureVisible(margin);
    await tester.pump();
    await tester.drag(margin, const Offset(80, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    final panel = tester.widget<Container>(
      find.byKey(const ValueKey('segment-panel')),
    );
    final paddingInsets = panel.padding! as EdgeInsets;
    final marginInsets = panel.margin! as EdgeInsets;
    expect(paddingInsets.left, greaterThan(20));
    expect(marginInsets.left, greaterThan(0));
  });

  testWidgets('fits the 8-segment panel at large padding and margin', (
    tester,
  ) async {
    final settings = ClockSettings()
      ..segmentPadding = 48
      ..segmentMargin = 48
      ..segmentScale = 1.2;
    final store = <String, String>{'settings': jsonEncode(settings.toJson())};
    final preferences = _MemoryPreferences(store);

    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final size in const [Size(390, 844), Size(844, 390)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        clockApp(
          face: ClockFace.segment,
          key: ValueKey(size),
          preferences: preferences,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('segment-panel')), findsOneWidget);
    }
  });

  testWidgets('follows orientation and supports forced layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = <String, String>{};
    final preferences = _MemoryPreferences(store);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpWidget(
      clockApp(face: ClockFace.flip, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('clock-layout-flip-portrait')),
      findsOneWidget,
    );

    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('clock-layout-flip-landscape')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('clock-settings')));
    await tester.pumpAndSettle();

    final portrait = find.text('Portrait');
    await tester.ensureVisible(portrait);
    await tester.pump();
    await tester.tap(portrait);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('clock-settings-close')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('clock-layout-flip-portrait')),
      findsOneWidget,
    );
  });

  testWidgets('every face fits each forced layout', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final layout in const [ClockLayout.portrait, ClockLayout.landscape]) {
      final settings = ClockSettings()..layout = layout;
      final preferences = _MemoryPreferences({
        'settings': jsonEncode(settings.toJson()),
      });
      for (final size in const [Size(390, 844), Size(844, 390)]) {
        tester.view.physicalSize = size;
        for (final face in ClockFace.values) {
          await tester.pumpWidget(
            clockApp(
              face: face,
              key: ValueKey('$layout-$size-${face.name}'),
              preferences: preferences,
            ),
          );
          await tester.pump();
          await tester.pumpAndSettle();

          final orientation = layout == ClockLayout.portrait
              ? 'portrait'
              : 'landscape';
          expect(
            find.byKey(ValueKey('clock-layout-${face.name}-$orientation')),
            findsOneWidget,
          );
        }
      }
    }
  });

  testWidgets('lays out every face in portrait and landscape', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final preferences = clockPreferences();
    for (final size in const [Size(390, 844), Size(844, 390)]) {
      tester.view.physicalSize = size;
      for (final face in ClockFace.values) {
        await tester.pumpWidget(
          clockApp(face: face, key: ValueKey(face), preferences: preferences),
        );
        await tester.pumpAndSettle();
        expect(find.text(face.englishName), findsOneWidget);
        final layout = size.width < size.height ? 'portrait' : 'landscape';
        expect(
          find.byKey(ValueKey('clock-layout-${face.name}-$layout')),
          findsOneWidget,
        );
      }
    }
  });
}
