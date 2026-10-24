import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pockito/main.dart';

void main() {
  group('frequency helpers', () {
    test('clamps frequencies to the audible slider range', () {
      expect(clampToneFrequency(10), toneMinFrequency);
      expect(clampToneFrequency(25000), toneMaxFrequency);
      expect(clampToneFrequency(440), 440);
      expect(clampToneFrequency(double.nan), 440);
      expect(clampToneFrequency(double.infinity), 440);
    });

    test('maps the slider logarithmically and round-trips', () {
      expect(toneSliderToFrequency(0), closeTo(toneMinFrequency, 0.001));
      expect(toneSliderToFrequency(1), closeTo(toneMaxFrequency, 0.001));
      for (final hz in [20.0, 100.0, 440.0, 1000.0, 12345.0, 20000.0]) {
        expect(
          toneSliderToFrequency(toneFrequencyToSlider(hz)),
          closeTo(hz, 0.001),
        );
      }
      expect(toneFrequencyToSlider(632.4555), closeTo(0.5, 0.001));
    });

    test('formats whole and fractional frequencies', () {
      expect(formatToneNumber(440), '440');
      expect(formatToneFrequency(1000), '1000 Hz');
      expect(formatToneNumber(1234.56), '1234.6');
      expect(formatToneFrequency(20), '20 Hz');
    });

    test('names the nearest note and its cents offset', () {
      final a4 = toneNoteForFrequency(440)!;
      expect(a4.name, 'A');
      expect(a4.octave, 4);
      expect(a4.cents, 0);
      expect(formatToneNote(a4), 'A4 0 ct');

      final c4 = toneNoteForFrequency(261.63)!;
      expect(c4.name, 'C');
      expect(c4.octave, 4);
      expect(c4.cents.abs(), lessThanOrEqualTo(1));

      final a5 = toneNoteForFrequency(880)!;
      expect(a5.name, 'A');
      expect(a5.octave, 5);
      expect(a5.cents, 0);

      final sharp = toneNoteForFrequency(452)!;
      expect(sharp.name, 'A');
      expect(sharp.cents, greaterThan(0));
      expect(formatToneNote(sharp), startsWith('A4 +'));
    });

    test('computes period and wavelength', () {
      expect(tonePeriodMilliseconds(1000), closeTo(1, 0.0001));
      expect(toneWavelengthCentimeters(1000), closeTo(34.3, 0.001));
      expect(tonePeriodMilliseconds(20), closeTo(50, 0.0001));
    });

    test('maps every waveform to a native waveform', () {
      expect(ToneWaveform.values, hasLength(4));
      expect(ToneWaveform.sine.nativeWaveform, WaveForm.sin);
      expect(ToneWaveform.triangle.nativeWaveform, WaveForm.triangle);
      for (final waveform in ToneWaveform.values) {
        expect(waveform.englishName, isNotEmpty);
        expect(waveform.chineseName, isNotEmpty);
      }
    });
  });

  testWidgets('shows the frequency generator controls', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Frequency Generator'), 200.0);
    await tester.tap(find.text('Frequency Generator'));
    await tester.pumpAndSettle();

    expect(find.text('Pure tone'), findsOneWidget);
    expect(find.text('440 Hz'), findsWidgets);
    expect(find.text('Exact frequency'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('Waveform'), findsOneWidget);
    expect(find.text('Sine'), findsOneWidget);
    expect(find.text('Square'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
  });

  testWidgets('accepts a custom frequency and rejects out-of-range values', (
    tester,
  ) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Frequency Generator'), 200.0);
    await tester.tap(find.text('Frequency Generator'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '1234.5');
    await tester.pump();
    expect(find.text('1234.5 Hz'), findsOneWidget);
    expect(find.textContaining('A4'), findsNothing);

    await tester.enterText(find.byType(TextField), '99999');
    await tester.pump();
    expect(
      find.text('Enter a frequency between 20 and 20,000 Hz.'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '440');
    await tester.pump();
    expect(find.text('A4 0 ct'), findsOneWidget);
  });
}
