import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reef/main.dart';

void main() {
  testWidgets('shows the tool list', (tester) async {
    await tester.pumpWidget(const VaultApp());

    expect(find.text('Reef'), findsOneWidget);
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

  testWidgets('opens the 2048 tool', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('2048'));
    await tester.pumpAndSettle();

    expect(find.text('Score'), findsOneWidget);
    expect(find.text('Best'), findsOneWidget);
    expect(find.byType(Game2048Screen), findsOneWidget);
  });

  testWidgets('renders a full 2048 grid', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('2048'));
    await tester.pumpAndSettle();

    for (final position in ['tile-0-0', 'tile-0-3', 'tile-3-0', 'tile-3-3']) {
      final cell = find.byKey(ValueKey(position));
      expect(cell, findsOneWidget);
      final size = tester.getSize(cell);
      expect(size.width, greaterThan(10));
      expect(size.height, greaterThan(10));
    }
  });

  testWidgets('switches the 2048 board size', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('2048'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.grid_on));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 × 5'));
    await tester.pumpAndSettle();

    expect(find.text('5 × 5'), findsOneWidget);
  });

  testWidgets('auto plays the 2048 tool', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('2048'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Auto play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byTooltip('Pause auto play'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause auto play'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Auto play'), findsOneWidget);
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

  testWidgets('opens the flashlight tool and converts morse', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(find.text('Flashlight'), 200.0);
    await tester.tap(find.text('Flashlight'));
    await tester.pumpAndSettle();

    expect(find.byType(FlashlightScreen), findsOneWidget);
    expect(find.textContaining('No flashlight'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'SOS');
    await tester.pumpAndSettle();

    expect(find.text('... --- ...'), findsOneWidget);
  });

  testWidgets('shows tic tac toe acknowledgements', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Acknowledgements'), findsOneWidget);
    expect(find.textContaining('open-source Dooz'), findsOneWidget);
  });

  testWidgets('opens the tic tac toe tool', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();

    expect(find.byType(TicTacToeScreen), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
  });

  testWidgets('lets the bot reply in tic tac toe', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tic-tac-toe-4')));
    await tester.pump();
    expect(find.text('X'), findsOneWidget);
    expect(find.text('Bot is thinking…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('O'), findsOneWidget);
  });

  testWidgets('customizes tic tac toe symbols', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'A');
    await tester.enterText(fields.at(1), 'B');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tic-tac-toe-0')));
    await tester.pump();
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('plays tic tac toe with two players', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Game mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two players'));
    await tester.pumpAndSettle();

    expect(find.text("X's turn"), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tic-tac-toe-4')));
    await tester.pump();
    expect(find.text("O's turn"), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("O's turn"), findsOneWidget);
  });

  testWidgets('keeps the board steady after a tic tac toe result', (
    tester,
  ) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Game mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two players'));
    await tester.pumpAndSettle();

    final before = tester.getSize(find.byKey(const ValueKey('tic-tac-toe-0')));

    for (final index in [0, 3, 1, 4, 2]) {
      await tester.tap(find.byKey(ValueKey('tic-tac-toe-$index')));
      await tester.pump();
    }

    expect(find.text('X wins!'), findsOneWidget);
    final after = tester.getSize(find.byKey(const ValueKey('tic-tac-toe-0')));
    expect(after, before);
  });

  testWidgets('ends tic tac toe early with quick result detection', (
    tester,
  ) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Game mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two players'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.flash_off), findsOneWidget);
    await tester.tap(find.byIcon(Icons.flash_off));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.flash_on), findsOneWidget);

    for (final index in [0, 3, 1, 4]) {
      await tester.tap(find.byKey(ValueKey('tic-tac-toe-$index')));
      await tester.pump();
    }

    expect(find.text('X wins!'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tic-tac-toe-2')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
  });

  testWidgets('detects a tic tac toe draw before the board fills', (
    tester,
  ) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Game mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two players'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.flash_off));
    await tester.pumpAndSettle();

    for (final index in [0, 4, 1, 2, 6, 3, 5, 7]) {
      await tester.tap(find.byKey(ValueKey('tic-tac-toe-$index')));
      await tester.pump();
    }

    expect(find.text('Draw'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tic-tac-toe-8')),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
  });
}
