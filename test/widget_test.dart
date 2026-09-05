import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:privacy_vault/main.dart';

void main() {
  testWidgets('shows the decoy password generator', (tester) async {
    await tester.pumpWidget(const VaultApp());

    expect(find.text('Password Generator'), findsOneWidget);
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
    await tester.pump();

    expect(find.text('密码生成器'), findsOneWidget);
    expect(find.text('字符筛选'), findsOneWidget);
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
}
