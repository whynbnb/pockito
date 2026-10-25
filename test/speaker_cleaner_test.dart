import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pockito/main.dart';

void main() {
  group('speaker cleaner helpers', () {
    test('clamps frequencies to the cleaning range', () {
      expect(clampSpeakerCleanerFrequency(165), 165);
      expect(clampSpeakerCleanerFrequency(10), speakerCleanerMinFrequency);
      expect(clampSpeakerCleanerFrequency(5000), speakerCleanerMaxFrequency);
      expect(
        clampSpeakerCleanerFrequency(double.nan),
        speakerCleanerDefaultFrequency,
      );
    });

    test('maps the slider logarithmically and round-trips', () {
      expect(
        speakerCleanerSliderToFrequency(0),
        closeTo(speakerCleanerMinFrequency, 0.001),
      );
      expect(
        speakerCleanerSliderToFrequency(1),
        closeTo(speakerCleanerMaxFrequency, 0.001),
      );
      final position = speakerCleanerFrequencyToSlider(165);
      expect(position, inInclusiveRange(0, 1));
      expect(speakerCleanerSliderToFrequency(position), closeTo(165, 0.001));
    });

    test('marks bursts and pauses across cycles', () {
      expect(speakerCleanerBurstActive(0, burstMs: 800, pauseMs: 250), isTrue);
      expect(
        speakerCleanerBurstActive(799, burstMs: 800, pauseMs: 250),
        isTrue,
      );
      expect(
        speakerCleanerBurstActive(800, burstMs: 800, pauseMs: 250),
        isFalse,
      );
      expect(
        speakerCleanerBurstActive(1049, burstMs: 800, pauseMs: 250),
        isFalse,
      );
      expect(
        speakerCleanerBurstActive(1050, burstMs: 800, pauseMs: 250),
        isTrue,
      );
    });

    test('counts pulses over the run duration', () {
      expect(
        speakerCleanerTotalPulses(
          const Duration(seconds: 20),
          burstMs: 800,
          pauseMs: 200,
        ),
        20,
      );
      expect(speakerCleanerPulseIndex(0, burstMs: 800, pauseMs: 200), 1);
      expect(speakerCleanerPulseIndex(1000, burstMs: 800, pauseMs: 200), 2);
    });

    test('formats burst and pause lengths', () {
      expect(formatSpeakerCleanerDuration(350), '350 ms');
      expect(formatSpeakerCleanerDuration(1000), '1 s');
      expect(formatSpeakerCleanerDuration(1500), '1.5 s');
    });

    test('presets stay inside the pulse ranges', () {
      expect(
        speakerCleanerRhythms.map((rhythm) => rhythm.id),
        containsAll(['gentle', 'standard', 'strong', 'rapid']),
      );
      for (final rhythm in speakerCleanerRhythms) {
        expect(
          rhythm.burstMs,
          inInclusiveRange(speakerCleanerMinBurstMs, speakerCleanerMaxBurstMs),
        );
        expect(
          rhythm.pauseMs,
          inInclusiveRange(speakerCleanerMinPauseMs, speakerCleanerMaxPauseMs),
        );
      }
    });
  });

  testWidgets('shows the speaker cleaner controls', (tester) async {
    tester.view.physicalSize = const Size(1200, 4600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Speaker Cleaner'), 200.0);
    await tester.tap(find.text('Speaker Cleaner'));
    await tester.pumpAndSettle();

    expect(find.text('Cleaning pulse'), findsOneWidget);
    expect(find.text('Pulse rhythm'), findsOneWidget);
    expect(find.text('Tone frequency'), findsOneWidget);
    expect(find.text('Cleaning time'), findsOneWidget);
    expect(find.text('Sync vibration'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('How to use it'), findsOneWidget);
    expect(find.text('Start cleaning'), findsOneWidget);
    expect(find.text('Standard'), findsOneWidget);
    expect(find.text('800 ms tone · 250 ms pause'), findsOneWidget);
  });

  testWidgets('validates the cleaning frequency', (tester) async {
    tester.view.physicalSize = const Size(1200, 4600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Speaker Cleaner'), 200.0);
    await tester.tap(find.text('Speaker Cleaner'));
    await tester.pumpAndSettle();

    final field = find.byKey(const ValueKey('speaker-cleaner-frequency-field'));

    await tester.enterText(field, '2000');
    await tester.pump();
    expect(
      find.text('Enter a frequency between 60 and 1,000 Hz.'),
      findsOneWidget,
    );

    await tester.enterText(field, '165');
    await tester.pump();
    expect(
      find.text('Enter a frequency between 60 and 1,000 Hz.'),
      findsNothing,
    );
  });

  testWidgets('selects a pulse rhythm and a cleaning time', (tester) async {
    tester.view.physicalSize = const Size(1200, 4600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Speaker Cleaner'), 200.0);
    await tester.tap(find.text('Speaker Cleaner'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rapid'));
    await tester.pump();
    expect(find.text('350 ms tone · 150 ms pause'), findsOneWidget);

    final thirtySeconds = find.byKey(
      const ValueKey('speaker-cleaner-duration-30'),
    );
    await tester.tap(thirtySeconds);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(thirtySeconds).selected, isTrue);
  });

  testWidgets('explains when vibration is unavailable', (tester) async {
    tester.view.physicalSize = const Size(1200, 4600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Speaker Cleaner'), 200.0);
    await tester.tap(find.text('Speaker Cleaner'));
    await tester.pumpAndSettle();

    final vibration = find.byKey(const ValueKey('speaker-cleaner-vibration'));
    expect(tester.widget<SwitchListTile>(vibration).onChanged, isNull);
    expect(
      find.text('No vibration motor on this device; audio pulses still work.'),
      findsOneWidget,
    );
  });
}
