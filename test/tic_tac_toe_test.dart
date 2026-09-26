import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:reef/main.dart';

TicTacToePlayer? p(String value) => switch (value) {
  'x' => TicTacToePlayer.x,
  'o' => TicTacToePlayer.o,
  _ => null,
};

TicTacToe board(String spec) =>
    TicTacToe(cells: spec.split('').map(p).toList());

void main() {
  test('tic tac toe detects row, column and diagonal winners', () {
    expect(board('xxx......').winner, TicTacToePlayer.x);
    expect(board('o..o..o..').winner, TicTacToePlayer.o);
    expect(board('o...o...o').winner, TicTacToePlayer.o);
    expect(board('x...x...x').winner, TicTacToePlayer.x);
    expect(board('..x.x.x..').winner, TicTacToePlayer.x);
  });

  test('tic tac toe reports no winner on an open board', () {
    expect(board('x.o......').winner, isNull);
    expect(board('x.o......').isOver, isFalse);
  });

  test('tic tac toe detects a draw', () {
    final game = board('xoxxoooxx');
    expect(game.winner, isNull);
    expect(game.isDraw, isTrue);
    expect(game.isOver, isTrue);
  });

  test('tic tac toe lists empty cells and rejects taken cells', () {
    final game = board('x.o......');
    expect(game.emptyCells, [1, 3, 4, 5, 6, 7, 8]);
    expect(game.play(0, TicTacToePlayer.o), isFalse);
    expect(game.play(1, TicTacToePlayer.o), isTrue);
    expect(game.cells[1], TicTacToePlayer.o);
  });

  test('tic tac toe reset clears the board', () {
    final game = board('xoxooxxox');
    game.reset();
    expect(game.cells.every((cell) => cell == null), isTrue);
  });

  test('bot takes an immediate winning move', () {
    final move = TicTacToeBot.chooseMove(
      board('oo.xx....').cells,
      self: TicTacToePlayer.o,
      opponent: TicTacToePlayer.x,
      difficulty: TicTacToeDifficulty.hard,
    );
    expect(move, 2);
  });

  test('bot blocks the opponent winning move', () {
    final move = TicTacToeBot.chooseMove(
      board('xx.o.....').cells,
      self: TicTacToePlayer.o,
      opponent: TicTacToePlayer.x,
      difficulty: TicTacToeDifficulty.hard,
    );
    expect(move, 2);
  });

  test('bot returns null when the board is full', () {
    final move = TicTacToeBot.chooseMove(
      board('xoxooxxox').cells,
      self: TicTacToePlayer.o,
      opponent: TicTacToePlayer.x,
    );
    expect(move, isNull);
  });

  test('easy bot only picks empty cells', () {
    final game = board('xo.......');
    for (var i = 0; i < 20; i++) {
      final move = TicTacToeBot.chooseMove(
        game.cells,
        self: TicTacToePlayer.o,
        opponent: TicTacToePlayer.x,
        difficulty: TicTacToeDifficulty.easy,
        random: Random(i),
      );
      expect(move, isNotNull);
      expect(game.cells[move!], isNull);
    }
  });

  test('forced winner is null on a drawn board', () {
    expect(
      TicTacToeBot.forcedWinner(List<TicTacToePlayer?>.filled(9, null)),
      isNull,
    );
  });

  test('forced winner detects an unavoidable win and loss', () {
    expect(
      TicTacToeBot.forcedWinner(board('xx.oo....').cells),
      TicTacToePlayer.x,
    );
    expect(
      TicTacToeBot.forcedWinner(board('xx.oo.x..').cells),
      TicTacToePlayer.o,
    );
  });

  test('forced winner detects a fork before the board is full', () {
    final game = board('xoo..x...');
    expect(game.winner, isNull);
    expect(game.isOver, isFalse);
    expect(TicTacToeBot.forcedWinner(game.cells), TicTacToePlayer.x);
  });

  test('dead draw is detected once no line can be completed', () {
    final dead = board('xoxxooox.');
    expect(dead.winner, isNull);
    expect(dead.isFull, isFalse);
    expect(dead.isDeadDraw, isTrue);
    expect(TicTacToeBot.forcedWinner(dead.cells), isNull);
  });

  test('dead draw is not reported while a line is still winnable', () {
    expect(board('xoxxoooxx').isDeadDraw, isTrue);
    expect(board('xx.......').isDeadDraw, isFalse);
    expect(board('.........').isDeadDraw, isFalse);
  });

  test('hard bot never loses against random play', () {
    final rng = Random(2026);
    for (var round = 0; round < 40; round++) {
      final game = TicTacToe();
      while (!game.isOver) {
        final empties = game.emptyCells;
        game.play(empties[rng.nextInt(empties.length)], TicTacToePlayer.x);
        if (game.isOver) break;
        final move = TicTacToeBot.chooseMove(
          game.cells,
          self: TicTacToePlayer.o,
          opponent: TicTacToePlayer.x,
          difficulty: TicTacToeDifficulty.hard,
          random: rng,
        );
        game.play(move!, TicTacToePlayer.o);
      }
      expect(game.winner, isNot(TicTacToePlayer.x));
    }
  });
}
