import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pockito/main.dart';

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

  test('tools without credits are marked false', () {
    expect(toolInfoById('basexx')!.hasAcknowledgements, isFalse);
    expect(toolInfoById('2048')!.hasAcknowledgements, isFalse);
    expect(toolInfoById('flashlight')!.hasAcknowledgements, isTrue);
    expect(toolInfoById('counter')!.hasAcknowledgements, isTrue);
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

  testWidgets('acknowledgements show a styled license and a link', (
    tester,
  ) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Password Generator'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.info_outline).first);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.verified_outlined), findsNWidgets(1));
    expect(find.textContaining('License: Apache License 2.0'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    expect(
      find.text('https://gitlab.com/vecturagames/passwordgenerator'),
      findsOneWidget,
    );
  });

  for (final tool in toolInfos.where((tool) => !tool.hasAcknowledgements)) {
    testWidgets('${tool.id} hides the info action', (tester) async {
      await tester.pumpWidget(const VaultApp());
      await tester.scrollUntilVisible(find.text(tool.englishTitle), 200.0);
      await tester.tap(find.text(tool.englishTitle));
      await tester.pumpAndSettle();

      expect(
        find.byIcon(Icons.info_outline),
        findsNothing,
        reason: '${tool.id} should not expose an info action',
      );
    });
  }

  for (final tool in toolInfos.where((tool) => tool.hasAcknowledgements)) {
    testWidgets('${tool.id} exposes the info interface', (tester) async {
      await tester.pumpWidget(const VaultApp());

      await tester.scrollUntilVisible(find.text(tool.englishTitle), 200.0);
      await tester.tap(find.text(tool.englishTitle));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.info_outline).first);
      await tester.pumpAndSettle();

      expect(find.text('Acknowledgements'), findsOneWidget);
      expect(find.textContaining(tool.credits.first.project), findsWidgets);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });
  }
}
