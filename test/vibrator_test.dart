import 'package:flutter_test/flutter_test.dart';

import 'package:pockito/main.dart';

void main() {
  test('parses comma and space separated durations', () {
    expect(parseVibrationPattern('200, 100, 200'), [200, 100, 200]);
    expect(parseVibrationPattern(' 80  80\n500 '), [80, 80, 500]);
    expect(parseVibrationPattern('80'), [80]);
  });

  test('rejects invalid patterns', () {
    expect(parseVibrationPattern(''), isNull);
    expect(parseVibrationPattern('   '), isNull);
    expect(parseVibrationPattern('100, abc'), isNull);
    expect(parseVibrationPattern('0, 100'), isNull);
    expect(parseVibrationPattern('-5'), isNull);
    expect(parseVibrationPattern('1000000'), isNull);
  });

  test('computes the total pattern duration', () {
    expect(vibrationPatternDuration([100, 50, 200]), 350);
    expect(vibrationPatternDuration(const []), 0);
  });

  test('formats a pattern', () {
    expect(formatVibrationPattern([200, 100, 50]), '200, 100, 50');
  });

  test('presets are well formed', () {
    expect(vibrationPresets, isNotEmpty);
    for (final preset in vibrationPresets) {
      expect(preset.id, isNotEmpty);
      expect(preset.englishName, isNotEmpty);
      expect(preset.chineseName, isNotEmpty);
      expect(preset.pattern, isNotEmpty);
      expect(preset.pattern.every((segment) => segment > 0), isTrue);
    }
    final ids = vibrationPresets.map((preset) => preset.id).toSet();
    expect(ids, hasLength(vibrationPresets.length));
  });

  test('crisp style turns each vibration into a single short click', () {
    expect(applyVibrationStyle([600, 100, 80], VibrationStyle.crisp), [
      20,
      100,
      20,
    ]);
  });

  test('crisp style leaves already short pulses untouched', () {
    expect(applyVibrationStyle([20, 100], VibrationStyle.crisp), [20, 100]);
  });

  test('soft and standard styles keep the pattern', () {
    const pattern = [200, 100, 200];
    expect(
      applyVibrationStyle(pattern, VibrationStyle.standard),
      same(pattern),
    );
    expect(applyVibrationStyle(pattern, VibrationStyle.soft), same(pattern));
  });

  test('sharpness rises from soft to crisp', () {
    expect(
      vibrationSharpness(VibrationStyle.soft),
      lessThan(vibrationSharpness(VibrationStyle.standard)),
    );
    expect(
      vibrationSharpness(VibrationStyle.standard),
      lessThan(vibrationSharpness(VibrationStyle.crisp)),
    );
  });
}
