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

  testWidgets('shows password generator acknowledgements', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Password Generator'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Acknowledgements'), findsOneWidget);
    expect(find.textContaining('Vectura Games'), findsOneWidget);
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
    final themeButton = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    final localeButton = tester.widget<SegmentedButton<LocaleMode>>(
      find.byType(SegmentedButton<LocaleMode>),
    );
    expect(themeButton.selected, {ThemeMode.system});
    expect(localeButton.selected, {LocaleMode.system});
  });

  testWidgets('follows the system language when set to System', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    await tester.pumpWidget(const VaultApp());
    await tester.pumpAndSettle();

    expect(find.text('密码生成器'), findsOneWidget);
    expect(find.text('Password Generator'), findsNothing);
  });

  testWidgets('encodes text with the Basexx tool', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Basexx'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Hello');
    await tester.tap(find.text('Encode'));
    await tester.pumpAndSettle();

    expect(find.text('SGVsbG8='), findsOneWidget);
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

  testWidgets('records counter history', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('+1 Counter'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New counter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), 'Water');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add one'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();

    expect(find.text('Counter history'), findsOneWidget);
    expect(find.text('Total after: 1'), findsOneWidget);
  });
}
