import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pockito/main.dart';

Finder homeScrollable() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

Future<void> openTool(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(
    find.text(title),
    200.0,
    scrollable: homeScrollable(),
  );
  await tester.ensureVisible(find.text(title));
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> openDetails(WidgetTester tester, String toolId) async {
  await tester.tap(find.byKey(ValueKey('tool-info-$toolId')));
  await tester.pumpAndSettle();
}

Future<void> scrollDetailsTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    200.0,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  test('every tool implements the info interface', () {
    expect(toolInfos, isNotEmpty);
    for (final tool in toolInfos) {
      expect(tool.id, isNotEmpty);
      expect(tool.englishTitle, isNotEmpty);
      expect(tool.chineseTitle, isNotEmpty);
      expect(tool.englishSubtitle, isNotEmpty);
      expect(tool.chineseSubtitle, isNotEmpty);
      expect(toolInfoById(tool.id), same(tool));
    }
    final ids = toolInfos.map((tool) => tool.id).toSet();
    expect(ids, hasLength(toolInfos.length));
  });

  test('every tool carries complete details', () {
    expect(
      toolDetailsById.keys.toSet(),
      toolInfos.map((tool) => tool.id).toSet(),
    );
    final date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    for (final tool in toolInfos) {
      final details = toolDetailsFor(tool.id);
      expect(details, isNotNull, reason: tool.id);
      expect(
        details!.tags.length,
        inInclusiveRange(2, 5),
        reason: '${tool.id} needs two to five tags',
      );
      for (final tag in details.tags) {
        expect(tag.english, isNotEmpty);
        expect(tag.chinese, isNotEmpty);
      }
      expect(details.scope.english, isNotEmpty);
      expect(details.scope.chinese, isNotEmpty);
      expect(details.limitations, isNotEmpty);
      for (final limitation in details.limitations) {
        expect(limitation.english, isNotEmpty);
        expect(limitation.chinese, isNotEmpty);
      }
      expect(
        details.platforms.map((status) => status.platform).toSet(),
        ToolPlatform.values.toSet(),
        reason: '${tool.id} should cover every platform',
      );
      expect(details.version, '1.0');
      expect(date.hasMatch(details.released), isTrue);
      expect(date.hasMatch(details.updated), isTrue);
      expect(
        details.updated.compareTo(details.released),
        greaterThanOrEqualTo(0),
      );
    }
  });

  test('tools without credits are marked false', () {
    expect(toolInfoById('basexx')!.hasAcknowledgements, isFalse);
    expect(toolInfoById('2048')!.hasAcknowledgements, isFalse);
    expect(toolInfoById('speaker-cleaner')!.hasAcknowledgements, isFalse);
    expect(toolInfoById('clock')!.hasAcknowledgements, isFalse);
    expect(toolInfoById('flashlight')!.hasAcknowledgements, isTrue);
    expect(toolInfoById('counter')!.hasAcknowledgements, isTrue);
    expect(toolInfoById('tone-generator')!.hasAcknowledgements, isTrue);
  });

  test('the frequency generator credits MotionEaseTune', () {
    final tool = toolInfoById('tone-generator')!;
    final credit = tool.credits.single;
    expect(credit.project, 'MotionEaseTune');
    expect(credit.author, 'BHznJNs');
    expect(credit.license, contains('General Public License'));
    expect(credit.url, 'https://github.com/BHznJNs/MotionEaseTune');
    expect(credit.englishDescription, contains('100 Hz'));
    expect(credit.chineseDescription, contains('100 Hz'));
  });

  test('credits carry a license and a url', () {
    for (final tool in toolInfos) {
      for (final credit in tool.credits) {
        expect(credit.project, isNotEmpty);
        expect(credit.author, isNotEmpty);
        expect(credit.license, isNotEmpty);
        expect(credit.url, startsWith('http'));
      }
    }
  });

  testWidgets('shows the tool details with every section', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());
    await openTool(tester, 'Password Generator');
    await openDetails(tester, 'password-generator');

    expect(find.byType(ToolDetailsScreen), findsOneWidget);
    expect(find.text('Tool details'), findsOneWidget);
    expect(find.text('Best for'), findsOneWidget);
    expect(find.text('Device support'), findsOneWidget);
    expect(
      find.textContaining('Generate passwords for websites'),
      findsOneWidget,
    );
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Generator'), findsOneWidget);
    expect(find.text('Version and dates'), findsOneWidget);
    expect(find.text('1.0'), findsOneWidget);
    expect(find.text('2026-09-05'), findsNWidgets(2));

    await scrollDetailsTo(tester, find.text('Known limitations'));
    expect(
      find.textContaining('Generated passwords stay in the app'),
      findsOneWidget,
    );

    await scrollDetailsTo(tester, find.text('Acknowledgements'));
    expect(find.byIcon(Icons.verified_outlined), findsOneWidget);
    expect(find.textContaining('License: Apache License 2.0'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    expect(
      find.text('https://gitlab.com/vecturagames/passwordgenerator'),
      findsOneWidget,
    );
  });

  testWidgets('reports partial and missing device support', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());
    await openTool(tester, 'Flashlight');
    await openDetails(tester, 'flashlight');

    await scrollDetailsTo(tester, find.text('Device support'));
    expect(find.text('Supported'), findsNWidgets(2));
    expect(find.text('Partial'), findsNWidgets(3));
    expect(
      find.textContaining('desktop platforms only offer Morse'),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openTool(tester, 'Vibrator');
    await openDetails(tester, 'vibrator');
    await scrollDetailsTo(tester, find.text('Device support'));
    expect(find.text('Not available'), findsNWidgets(3));
  });

  testWidgets('shows the tone generator credit in the details', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const VaultApp());
    await openTool(tester, 'Frequency Generator');
    await openDetails(tester, 'tone-generator');

    await scrollDetailsTo(tester, find.text('Acknowledgements'));
    expect(find.textContaining('100 Hz motion'), findsWidgets);
    expect(
      find.textContaining('License: GNU General Public License v3.0'),
      findsOneWidget,
    );
    expect(
      find.text('https://github.com/BHznJNs/MotionEaseTune'),
      findsOneWidget,
    );
  });

  for (final tool in toolInfos) {
    testWidgets('${tool.id} opens its details page', (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const VaultApp());
      await openTool(tester, tool.englishTitle);

      final action = find.byKey(ValueKey('tool-info-${tool.id}'));
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.byType(ToolDetailsScreen), findsOneWidget);
      expect(find.byKey(ValueKey('tool-details-${tool.id}')), findsOneWidget);
      expect(find.text('Tool details'), findsOneWidget);
      expect(find.text(tool.englishTitle), findsOneWidget);
      expect(
        find.text(toolDetailsFor(tool.id)!.tags.first.english),
        findsOneWidget,
      );
      expect(find.text('Best for'), findsOneWidget);
      expect(find.text('Device support'), findsOneWidget);
    });
  }
}
