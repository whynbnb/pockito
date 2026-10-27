import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pockito/main.dart';

Finder homeScrollable() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

class _MemoryPreferences extends LocalPreferences {
  _MemoryPreferences(this.values);

  final Map<String, String> values;

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  testWidgets('shows the tool list', (tester) async {
    await tester.pumpWidget(const VaultApp());

    expect(find.text('Pockito'), findsOneWidget);
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
    await tester.pumpWidget(
      VaultApp(preferences: _MemoryPreferences(<String, String>{})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('中文'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-nav-all')));
    await tester.pumpAndSettle();

    expect(find.text('密码生成器'), findsOneWidget);
    expect(find.text('+1 计数器'), findsOneWidget);
  });

  testWidgets('offers parallel system appearance and language choices', (
    tester,
  ) async {
    await tester.pumpWidget(
      VaultApp(preferences: _MemoryPreferences(<String, String>{})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('home-nav-settings')));
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

    await tester.pumpWidget(
      VaultApp(preferences: _MemoryPreferences(<String, String>{})),
    );
    await tester.pumpAndSettle();

    expect(find.text('密码生成器'), findsOneWidget);
    expect(find.text('Password Generator'), findsNothing);
  });

  testWidgets('encodes text with the Basexx tool', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(
      find.text('Basexx'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Basexx'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basexx'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Hello');
    await tester.tap(find.text('Encode'));
    await tester.pumpAndSettle();

    expect(find.text('SGVsbG8='), findsOneWidget);
  });

  testWidgets('opens the 2048 tool', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(
      find.text('2048'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('2048'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2048'));
    await tester.pumpAndSettle();

    expect(find.text('Score'), findsOneWidget);
    expect(find.text('Best'), findsOneWidget);
    expect(find.byType(Game2048Screen), findsOneWidget);
  });

  testWidgets('renders a full 2048 grid', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(
      find.text('2048'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('2048'));
    await tester.pumpAndSettle();
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

    await tester.scrollUntilVisible(
      find.text('2048'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('2048'));
    await tester.pumpAndSettle();
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

    await tester.scrollUntilVisible(
      find.text('2048'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('2048'));
    await tester.pumpAndSettle();
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

    await tester.scrollUntilVisible(
      find.text('Flashlight'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Flashlight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flashlight'));
    await tester.pumpAndSettle();

    expect(find.byType(FlashlightScreen), findsOneWidget);
    expect(find.textContaining('No flashlight'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'SOS');
    await tester.pumpAndSettle();

    expect(find.text('... --- ...'), findsOneWidget);
  });

  testWidgets('shows flashlight acknowledgements', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(
      find.text('Flashlight'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Flashlight'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flashlight'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Acknowledgements'), findsOneWidget);
    expect(find.textContaining('FlashDim'), findsOneWidget);
  });

  testWidgets('opens the vibrator tool and previews patterns', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(
      find.text('Vibrator'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Vibrator'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vibrator'));
    await tester.pumpAndSettle();

    expect(find.byType(VibratorScreen), findsOneWidget);
    expect(find.textContaining('No vibration motor'), findsOneWidget);
    expect(find.text('Tap'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Custom pattern'),
      200.0,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.enterText(find.byType(TextField), '200, 100');
    await tester.pumpAndSettle();

    expect(find.textContaining('total 300 ms'), findsOneWidget);
  });

  testWidgets('shows counter acknowledgements', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('+1 Counter'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Acknowledgements'), findsOneWidget);
    expect(find.textContaining('Counters'), findsOneWidget);
  });

  testWidgets('opens the game counter and increments a player', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Game Counter'));
    await tester.pumpAndSettle();

    expect(find.byType(GameCounterScreen), findsOneWidget);
    expect(find.text('Score'), findsNWidgets(2));
    expect(find.text('P1'), findsOneWidget);
    expect(find.text('P2'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(2));

    await tester.tap(find.text('0').first);
    await tester.pumpAndSettle();

    expect(find.text('1'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('records game counter history', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Game Counter'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('0').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();

    expect(find.byType(GameCounterHistoryScreen), findsOneWidget);
    expect(find.textContaining('+1'), findsOneWidget);
    expect(find.textContaining('Score'), findsOneWidget);
  });

  testWidgets('adds a game counter scene in settings', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Game Counter'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.byType(GameCounterSettingsScreen), findsOneWidget);

    await tester.tap(find.text('New scene'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), 'Poker');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Poker'), findsOneWidget);
  });

  testWidgets('adds a shared counter type in settings', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Game Counter'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add type'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), 'Armor');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Armor'), findsOneWidget);
  });

  testWidgets('sets the number of players in settings', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Game Counter'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Player 1'), findsOneWidget);
    expect(find.text('Player 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Increase'));
    await tester.pumpAndSettle();

    expect(find.text('Player 3'), findsOneWidget);
  });

  testWidgets('resets all counters from the main screen', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Game Counter'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('0').first);
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.byTooltip('Reset all counters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(find.text('0'), findsNWidgets(2));
  });

  testWidgets('sets the default quick tap direction', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Game Counter'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add one').first);
    await tester.tap(find.byTooltip('Add one').first);
    await tester.tap(find.byTooltip('Add one').first);
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Quick tap: +1'), findsOneWidget);
    await tester.tap(find.byTooltip('Toggle quick tap direction'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Quick tap: -1'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('sets a counter type default value', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Game Counter'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Set default value'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Default: 5'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('5'), findsNWidgets(2));
  });

  testWidgets('shows game counter acknowledgements', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Game Counter'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Acknowledgements'), findsOneWidget);
    expect(find.textContaining('open-source gamecounter'), findsOneWidget);
  });

  testWidgets('switches game scenes from the app bar', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.tap(find.text('Game Counter'));
    await tester.pumpAndSettle();

    expect(find.text('Game 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch scene'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manage scenes…'));
    await tester.pumpAndSettle();

    expect(find.byType(GameCounterSettingsScreen), findsOneWidget);
  });

  testWidgets('shows tic tac toe acknowledgements', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(
      find.text('Tic-Tac-Toe'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Acknowledgements'), findsOneWidget);
    expect(find.textContaining('open-source Dooz'), findsOneWidget);
  });

  testWidgets('opens the tic tac toe tool', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(
      find.text('Tic-Tac-Toe'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();

    expect(find.byType(TicTacToeScreen), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
  });

  testWidgets('lets the bot reply in tic tac toe', (tester) async {
    await tester.pumpWidget(const VaultApp());

    await tester.scrollUntilVisible(
      find.text('Tic-Tac-Toe'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();
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

    await tester.scrollUntilVisible(
      find.text('Tic-Tac-Toe'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();
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

    await tester.scrollUntilVisible(
      find.text('Tic-Tac-Toe'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();
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

    await tester.scrollUntilVisible(
      find.text('Tic-Tac-Toe'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();
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

    await tester.scrollUntilVisible(
      find.text('Tic-Tac-Toe'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();
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

    await tester.scrollUntilVisible(
      find.text('Tic-Tac-Toe'),
      200.0,
      scrollable: homeScrollable(),
    );
    await tester.ensureVisible(find.text('Tic-Tac-Toe'));
    await tester.pumpAndSettle();
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
