import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pockito/main.dart';
import 'package:timezone/timezone.dart' as tz;

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

Widget worldClockApp({Key? key, LocalPreferences? preferences}) => VaultApp(
  home: WorldClockScreen(
    key: key,
    preferences: preferences ?? _MemoryPreferences(<String, String>{}),
  ),
);

void main() {
  test('world cities have unique ids and valid time zones', () {
    ensureWorldTimeZones();
    final ids = worldCities.map((city) => city.id).toSet();
    expect(ids.length, worldCities.length);
    for (final city in worldCities) {
      expect(city.englishName, isNotEmpty);
      expect(city.chineseName, isNotEmpty);
      expect(city.code, isNotEmpty);
      if (city.timeZone != null) {
        expect(() => tz.getLocation(city.timeZone!), returnsNormally);
      }
    }
    expect(worldCityById('local'), same(localWorldCity));
    expect(worldCityById('missing'), isNull);
  });

  test('formats positive, negative and fractional offsets', () {
    expect(worldClockOffsetLabel(Duration.zero), 'UTC+00:00');
    expect(worldClockOffsetLabel(const Duration(hours: 8)), 'UTC+08:00');
    expect(
      worldClockOffsetLabel(const Duration(hours: 5, minutes: 30)),
      'UTC+05:30',
    );
    expect(worldClockOffsetLabel(const Duration(minutes: -270)), 'UTC-04:30');
  });

  test('converts instants with daylight saving', () {
    final winter = DateTime.utc(2026, 1, 15, 12);
    final summer = DateTime.utc(2026, 7, 15, 12);
    final newYork = worldCityById('new-york')!;
    final london = worldCityById('london')!;
    final shanghai = worldCityById('shanghai')!;

    expect(worldCityTime(newYork, winter).hour, 7);
    expect(worldCityTime(newYork, summer).hour, 8);
    expect(worldCityTime(london, winter).hour, 12);
    expect(worldCityTime(london, summer).hour, 13);
    expect(worldCityTime(shanghai, winter).hour, 20);
    expect(worldCityTime(localWorldCity, winter), winter);
  });

  test('world clock settings round-trip, dedupe and reject unknown cities', () {
    final settings = WorldClockSettings()
      ..cityIds = ['tokyo', 'paris', 'tokyo', 'missing']
      ..use24Hour = false
      ..showSeconds = true
      ..showDate = false
      ..signMode = WorldSignMode.flip;
    final restored = WorldClockSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>,
    );
    expect(restored.cityIds, ['tokyo', 'paris']);
    expect(restored.use24Hour, isFalse);
    expect(restored.showSeconds, isTrue);
    expect(restored.showDate, isFalse);
    expect(restored.signMode, WorldSignMode.flip);

    final defaults = WorldClockSettings();
    expect(defaults.cityIds, defaultWorldCityIds);
    expect(defaults.use24Hour, isTrue);
    expect(defaults.showSeconds, isFalse);
    expect(defaults.showDate, isTrue);
    expect(defaults.signMode, WorldSignMode.text);

    final empty = WorldClockSettings.fromJson({'cities': <String>[]});
    expect(empty.cityIds, isEmpty);

    final invalid = WorldClockSettings.fromJson({
      'cities': 'nope',
      'use24': 'yes',
      'seconds': 1,
      'date': null,
      'signMode': 'hologram',
    });
    expect(invalid.cityIds, defaultWorldCityIds);
    expect(invalid.use24Hour, isTrue);
    expect(invalid.showSeconds, isFalse);
    expect(invalid.showDate, isTrue);
    expect(invalid.signMode, WorldSignMode.text);

    settings.reset();
    expect(settings.cityIds, defaultWorldCityIds);
    expect(settings.use24Hour, isTrue);
    expect(settings.showSeconds, isFalse);
    expect(settings.showDate, isTrue);
    expect(settings.signMode, WorldSignMode.text);
  });

  testWidgets('opens the world clock from the tool list', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('World Clock'), 200.0);
    await tester.ensureVisible(find.text('World Clock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('World Clock'));
    await tester.pumpAndSettle();

    expect(find.byType(WorldClockScreen), findsOneWidget);
    expect(find.text('WORLD TIME'), findsOneWidget);
    expect(find.text('LOCAL'), findsOneWidget);
    expect(find.text('LONDON'), findsOneWidget);
    expect(find.text('NEW YORK'), findsOneWidget);
    expect(find.text('TOKYO'), findsOneWidget);
    expect(find.text('JFK'), findsOneWidget);
    expect(find.byKey(const ValueKey('world-clock-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('world-clock-settings')), findsOneWidget);
  });

  testWidgets('shows flip cards, codes and meta for the default board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(worldClockApp());
    await tester.pumpAndSettle();

    for (final id in defaultWorldCityIds) {
      expect(find.byKey(ValueKey('world-clock-city-$id')), findsOneWidget);
      expect(find.byKey(ValueKey('world-clock-time-$id')), findsOneWidget);
      expect(find.byKey(ValueKey('world-clock-meta-$id')), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('world-clock-seconds-tokyo')),
      findsNothing,
    );

    final cards = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_FlipCard',
    );
    expect(cards, findsWidgets);
  });

  testWidgets('toggles time format, seconds and date from board settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = <String, String>{};
    final preferences = _MemoryPreferences(store);

    await tester.pumpWidget(worldClockApp(preferences: preferences));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('world-clock-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Board settings'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('world-clock-use24')));
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('world-clock-use24')),
          )
          .value,
      isFalse,
    );
    expect(find.textContaining(RegExp(r'^(AM|PM)$')), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('world-clock-seconds')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('world-clock-seconds-tokyo')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('world-clock-date')));
    await tester.pump();
    expect(find.byKey(const ValueKey('world-clock-meta-tokyo')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('world-clock-reset')));
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('world-clock-use24')),
          )
          .value,
      isFalse,
    );
    expect(
      find.byKey(const ValueKey('world-clock-time-tokyo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('world-clock-seconds-tokyo')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('world-clock-meta-tokyo')), findsNothing);

    Navigator.of(
      tester.element(find.byKey(const ValueKey('world-clock-settings'))),
    ).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));

    final saved = jsonDecode(store['settings']!) as Map<String, dynamic>;
    expect(saved['use24'], isFalse);
    expect(saved['seconds'], isTrue);
    expect(saved['date'], isFalse);
  });

  testWidgets('fits a narrow phone board with seconds and 12-hour time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = WorldClockSettings()
      ..use24Hour = false
      ..showSeconds = true
      ..signMode = WorldSignMode.flip;
    await tester.pumpWidget(
      worldClockApp(
        preferences: _MemoryPreferences({
          'settings': jsonEncode(settings.toJson()),
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('world-clock-city-local')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('world-clock-seconds-local')),
      findsOneWidget,
    );
  });

  testWidgets('switches city signs to flip cards and persists the mode', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = <String, String>{};
    await tester.pumpWidget(
      worldClockApp(preferences: _MemoryPreferences(store)),
    );
    await tester.pumpAndSettle();

    expect(find.text('NEW YORK'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('world-clock-sign-new-york')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('world-clock-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flip'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('world-clock-sign-new-york')),
      findsOneWidget,
    );
    expect(find.text('NEW YORK'), findsNothing);

    Navigator.of(
      tester.element(find.byKey(const ValueKey('world-clock-settings'))),
    ).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));

    final saved = jsonDecode(store['settings']!) as Map<String, dynamic>;
    expect(saved['signMode'], 'flip');

    await tester.pumpWidget(
      worldClockApp(
        key: const ValueKey('reloaded'),
        preferences: _MemoryPreferences(store),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('world-clock-sign-new-york')),
      findsOneWidget,
    );
  });

  testWidgets('adds a city, persists it and removes it', (tester) async {
    tester.view.physicalSize = const Size(1100, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = <String, String>{};
    await tester.pumpWidget(
      worldClockApp(preferences: _MemoryPreferences(store)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('world-clock-add')));
    await tester.pumpAndSettle();
    expect(find.text('Add cities'), findsOneWidget);

    final search = find.byKey(const ValueKey('world-clock-search'));
    await tester.enterText(search, 'paris');
    await tester.pumpAndSettle();

    final paris = find.byKey(const ValueKey('world-clock-picker-paris'));
    expect(paris, findsOneWidget);
    await tester.tap(paris);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(paris).value, isTrue);

    await tester.tap(find.byKey(const ValueKey('world-clock-picker-done')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('world-clock-city-paris')),
      findsOneWidget,
    );
    expect(find.text('PARIS'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    var saved = jsonDecode(store['settings']!) as Map<String, dynamic>;
    expect(saved['cities'], contains('paris'));

    await tester.pumpWidget(
      worldClockApp(
        key: const ValueKey('reloaded'),
        preferences: _MemoryPreferences(store),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('world-clock-city-paris')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('world-clock-remove-paris')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('world-clock-city-paris')), findsNothing);
    await tester.pump(const Duration(milliseconds: 250));
    saved = jsonDecode(store['settings']!) as Map<String, dynamic>;
    expect(saved['cities'], isNot(contains('paris')));
  });

  testWidgets('shows an empty board and can add the first city', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = WorldClockSettings()..cityIds = [];
    await tester.pumpWidget(
      worldClockApp(
        preferences: _MemoryPreferences({
          'settings': jsonEncode(settings.toJson()),
        }),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('world-clock-empty')), findsOneWidget);
    expect(find.text('The board is empty'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('world-clock-empty-add')));
    await tester.pumpAndSettle();
    expect(find.text('Add cities'), findsOneWidget);

    final search = find.byKey(const ValueKey('world-clock-search'));
    await tester.enterText(search, 'tokyo');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('world-clock-picker-tokyo')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('world-clock-picker-done')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('world-clock-city-tokyo')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('world-clock-empty')), findsNothing);
  });
}
