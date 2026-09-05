import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:privacy_vault/main.dart';

void main() {
  testWidgets('shows the decoy password generator', (tester) async {
    await tester.pumpWidget(const VaultApp());

    expect(find.text('Password Generator'), findsOneWidget);
    expect(find.text('Include symbols'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });
}
