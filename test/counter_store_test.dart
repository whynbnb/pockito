import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reef/main.dart';

void main() {
  test('counter store persists counters and their records', () async {
    final directory = await Directory.systemTemp.createTemp('counters');
    addTearDown(() => directory.delete(recursive: true));

    final item = CounterItem(
      id: 'counter-1',
      name: 'Coffee',
      count: 3,
      updatedAt: DateTime(2026, 1, 1, 9, 30),
    );
    item.records.add(
      CounterRecord(time: DateTime(2026, 1, 1, 8), delta: 1, value: 3),
    );

    await CounterStore(directory).save([item]);
    final loaded = await CounterStore(directory).load();

    expect(loaded, hasLength(1));
    expect(loaded.first.name, 'Coffee');
    expect(loaded.first.count, 3);
    expect(loaded.first.updatedAt, DateTime(2026, 1, 1, 9, 30));
    expect(loaded.first.records, hasLength(1));
    expect(loaded.first.records.first.delta, 1);
    expect(loaded.first.records.first.value, 3);
  });

  test('local preferences persist simple values', () async {
    final directory = await Directory.systemTemp.createTemp('prefs');
    addTearDown(() => directory.delete(recursive: true));

    await LocalPreferences(directory).setString('ui_theme', 'dark');
    await LocalPreferences(directory).setString('ui_language', 'zh');

    final preferences = LocalPreferences(directory);
    expect(await preferences.getString('ui_theme'), 'dark');
    expect(await preferences.getString('ui_language'), 'zh');
    expect(await preferences.getString('missing'), isNull);
  });
}
