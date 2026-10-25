import 'dart:math';

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

    test('formats the remaining playback time', () {
      expect(formatCountdown(const Duration(minutes: 1)), '1:00');
      expect(formatCountdown(const Duration(seconds: 65)), '1:05');
      expect(formatCountdown(const Duration(seconds: 9)), '0:09');
      expect(formatCountdown(Duration.zero), '0:00');
      expect(formatCountdown(const Duration(seconds: -3)), '0:00');
      expect(formatCountdown(const Duration(minutes: 30)), '30:00');
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

    test('maps channels to stereo pan', () {
      expect(ToneChannel.both.pan, 0);
      expect(ToneChannel.left.pan, -1);
      expect(ToneChannel.right.pan, 1);
    });

    test('splits headroom between simultaneous layers', () {
      ToneLayer layer(String id, ToneChannel channel) =>
          ToneLayer(id: id, frequency: 440, channel: channel);

      expect(toneLayerGains([layer('a', ToneChannel.both)])['a'], 1);
      expect(
        toneLayerGains([
          layer('left', ToneChannel.left),
          layer('right', ToneChannel.right),
        ]),
        {'left': 1.0, 'right': 1.0},
      );
      expect(
        toneLayerGains([
          layer('a', ToneChannel.both),
          layer('b', ToneChannel.both),
        ]),
        {'a': 0.5, 'b': 0.5},
      );
      expect(
        toneLayerGains([
          layer('left', ToneChannel.left),
          layer('right', ToneChannel.right),
          layer('both', ToneChannel.both),
        ]),
        {'left': 0.5, 'right': 0.5, 'both': 0.5},
      );
    });

    test('interpolates linear and logarithmic sweeps', () {
      const from = 440.0;
      const to = 880.0;
      expect(
        toneSweepFrequency(from: from, to: to, progress: 0, logarithmic: true),
        closeTo(from, 0.001),
      );
      expect(
        toneSweepFrequency(from: from, to: to, progress: 1, logarithmic: true),
        closeTo(to, 0.001),
      );
      expect(
        toneSweepFrequency(
          from: from,
          to: to,
          progress: 0.5,
          logarithmic: true,
        ),
        closeTo(440 * sqrt2, 0.001),
      );
      expect(
        toneSweepFrequency(
          from: from,
          to: to,
          progress: 0.5,
          logarithmic: false,
        ),
        closeTo(660, 0.001),
      );
      expect(
        toneSweepFrequency(
          from: to,
          to: from,
          progress: 0.5,
          logarithmic: true,
        ),
        closeTo(440 * sqrt2, 0.001),
      );
      expect(
        toneSweepFrequency(from: from, to: to, progress: -1, logarithmic: true),
        closeTo(from, 0.001),
      );
      expect(
        toneSweepFrequency(from: from, to: to, progress: 2, logarithmic: true),
        closeTo(to, 0.001),
      );
    });

    test('computes one-shot and ping-pong sweep progress', () {
      expect(toneSweepProgress(0, 1000, false), 0);
      expect(toneSweepProgress(500, 1000, false), 0.5);
      expect(toneSweepProgress(1000, 1000, false), 1);
      expect(toneSweepProgress(2000, 1000, false), 1);
      expect(toneSweepProgress(500, 1000, true), 0.5);
      expect(toneSweepProgress(1000, 1000, true), 1);
      expect(toneSweepProgress(1500, 1000, true), 0.5);
      expect(toneSweepProgress(2000, 1000, true), 0);
      expect(toneSweepProgress(500, 0, false), 1);
    });

    test('picks a sensible default sweep target', () {
      expect(defaultSweepTarget(440), 880);
      expect(defaultSweepTarget(20), 40);
      expect(defaultSweepTarget(15000), 7500);
      expect(defaultSweepTarget(20000), 10000);
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

    await tester.enterText(
      find.byKey(const ValueKey('tone-frequency-field')),
      '1234.5',
    );
    await tester.pump();
    expect(find.text('1234.5 Hz'), findsWidgets);
    expect(find.textContaining('A4'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('tone-frequency-field')),
      '99999',
    );
    await tester.pump();
    expect(
      find.text('Enter a frequency between 20 and 20,000 Hz.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('tone-frequency-field')),
      '440',
    );
    await tester.pump();
    expect(find.text('A4 0 ct'), findsOneWidget);
  });

  testWidgets('selects a playback duration and shows the background note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Frequency Generator'), 200.0);
    await tester.tap(find.text('Frequency Generator'));
    await tester.pumpAndSettle();

    expect(find.text('Playback time'), findsOneWidget);
    expect(find.text('No limit'), findsOneWidget);
    expect(find.text('1 min'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('10 min'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(
      find.textContaining('switch apps or lock the screen'),
      findsOneWidget,
    );

    ChoiceChip chipFor(String label) => tester.widget<ChoiceChip>(
      find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip)),
    );

    expect(chipFor('No limit').selected, isTrue);

    await tester.tap(find.text('5 min'));
    await tester.pump();
    expect(chipFor('5 min').selected, isTrue);
    expect(chipFor('No limit').selected, isFalse);

    await tester.tap(find.text('No limit'));
    await tester.pump();
    expect(chipFor('No limit').selected, isTrue);
    expect(chipFor('5 min').selected, isFalse);
  });

  testWidgets('adds tones and assigns a channel', (tester) async {
    tester.view.physicalSize = const Size(1200, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Frequency Generator'), 200.0);
    await tester.tap(find.text('Frequency Generator'));
    await tester.pumpAndSettle();

    expect(find.text('Tones'), findsOneWidget);
    expect(find.text('Both channels'), findsOneWidget);
    expect(find.text('Tone 1/1'), findsNothing);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(find.text('880 Hz'), findsWidgets);
    expect(find.text('Tone 2/2'), findsOneWidget);
    expect(find.text('Both channels'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('tone-channel-tone-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Left channel').last);
    await tester.pumpAndSettle();

    expect(find.text('Left channel'), findsWidgets);
    expect(find.text('Tone 2/2 · Left channel'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove tone').last);
    await tester.pumpAndSettle();

    expect(find.text('880 Hz'), findsNothing);
    expect(find.text('Tone 2/2'), findsNothing);
    expect(find.text('Tone 1/1'), findsNothing);
  });

  testWidgets('configures a frequency sweep', (tester) async {
    tester.view.physicalSize = const Size(1200, 4400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Frequency Generator'), 200.0);
    await tester.tap(find.text('Frequency Generator'));
    await tester.pumpAndSettle();

    expect(find.text('Frequency sweep'), findsOneWidget);
    expect(find.text('Exact frequency'), findsOneWidget);

    final switchFinder = find.byKey(const ValueKey('tone-sweep-switch'));
    expect(tester.widget<Switch>(switchFinder).value, isFalse);

    await tester.tap(switchFinder);
    await tester.pump();

    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    // The manual frequency card is replaced by the sweep range.
    expect(find.text('Exact frequency'), findsNothing);

    final fromFinder = find.byKey(const ValueKey('tone-sweep-from'));
    final endFinder = find.byKey(const ValueKey('tone-sweep-end'));
    final durationFinder = find.byKey(const ValueKey('tone-sweep-duration'));

    expect(tester.widget<TextField>(fromFinder).controller!.text, '440');
    expect(tester.widget<TextField>(endFinder).controller!.text, '880');
    expect(tester.widget<TextField>(durationFinder).controller!.text, '10');

    await tester.enterText(fromFinder, '300');
    await tester.enterText(endFinder, '1200');
    await tester.enterText(durationFinder, '30');
    await tester.pump();

    await tester.enterText(fromFinder, '99999');
    await tester.pump();
    expect(
      find.text('Enter a start frequency between 20 and 20,000 Hz.'),
      findsOneWidget,
    );

    await tester.enterText(endFinder, '99999');
    await tester.pump();
    expect(
      find.text('Enter an end frequency between 20 and 20,000 Hz.'),
      findsOneWidget,
    );

    await tester.enterText(durationFinder, '0');
    await tester.pump();
    expect(
      find.text('Enter a duration between 1 and 3600 seconds.'),
      findsOneWidget,
    );

    await tester.enterText(fromFinder, '300');
    await tester.enterText(endFinder, '1200');
    await tester.enterText(durationFinder, '30');
    await tester.pump();

    final repeatFinder = find.byKey(const ValueKey('tone-sweep-repeat'));
    expect(tester.widget<SwitchListTile>(repeatFinder).value, isFalse);
    await tester.tap(repeatFinder);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(repeatFinder).value, isTrue);

    await tester.tap(find.text('Linear'));
    await tester.pump();
    var curve = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(curve.selected, {false});

    await tester.tap(find.text('Logarithmic'));
    await tester.pump();
    curve = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(curve.selected, {true});

    // Turning the sweep off brings the manual frequency card back.
    await tester.tap(switchFinder);
    await tester.pump();
    expect(find.text('Exact frequency'), findsOneWidget);
  });

  testWidgets('explains the 100 Hz motion sickness note', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Frequency Generator'), 200.0);
    await tester.tap(find.text('Frequency Generator'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tone-preset-info-100')), findsOneWidget);
    expect(find.text('A4 0 ct'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tone-preset-info-100')));
    await tester.pumpAndSettle();

    expect(find.text('100 Hz and motion sickness'), findsOneWidget);
    expect(find.textContaining('80–85 dBZ'), findsOneWidget);
    expect(find.text(motionSicknessStudyTitle), findsOneWidget);
    expect(find.text(motionSicknessStudyUrl), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Opening the note must not change the current tone.
    expect(find.text('A4 0 ct'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tone-preset-info-100')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use 100 Hz'));
    await tester.pumpAndSettle();

    expect(find.text('100 Hz'), findsWidgets);
    expect(find.textContaining('G2'), findsOneWidget);
    final sineChip = tester.widget<ChoiceChip>(
      find.ancestor(of: find.text('Sine'), matching: find.byType(ChoiceChip)),
    );
    expect(sineChip.selected, isTrue);
  });
}
