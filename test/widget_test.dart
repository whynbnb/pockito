import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:privacy_vault/main.dart';

void main() {
  testWidgets('shows the tool list', (tester) async {
    await tester.pumpWidget(const VaultApp());

    expect(find.text('Utility Kit'), findsOneWidget);
    expect(find.text('Password Generator'), findsOneWidget);
    expect(find.text('+1 Counter'), findsOneWidget);
  });

  testWidgets('opens the password generator tool', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Password Generator'));
    await tester.pumpAndSettle();

    expect(find.text('Character filters'), findsOneWidget);
    expect(find.text('Lowercase'), findsOneWidget);
    expect(find.text('Uppercase'), findsOneWidget);
    expect(find.text('Numbers'), findsOneWidget);
    expect(find.text('Special characters'), findsOneWidget);
    expect(find.text('Unique characters'), findsOneWidget);
    expect(find.text('Additional seed'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('changes the shared interface language', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();

    expect(find.text('密码生成器'), findsOneWidget);
    expect(find.text('+1 计数器'), findsOneWidget);
  });

  testWidgets('offers parallel system appearance and language choices', (
    tester,
  ) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('System'), findsNWidgets(2));
    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
    expect(find.byType(SegmentedButton<LocaleMode>), findsOneWidget);
  });

  testWidgets('counts custom events with the +1 tool', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('+1 Counter'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New counter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), 'Coffee');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byTooltip('Add one'));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
  });
}
