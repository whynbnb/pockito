import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pockito/main.dart';

void main() {
  test('2048 merges equal adjacent tiles once per move', () {
    final game = Game2048.withCells([
      2,
      2,
      2,
      2,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);

    expect(game.move(Direction2048.left, spawn: false), isTrue);
    expect(game.cells.sublist(0, 4), [4, 4, 0, 0]);
    expect(game.score, 8);
  });

  test('2048 merges toward the right', () {
    final game = Game2048.withCells([
      0,
      4,
      4,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);

    game.move(Direction2048.right, spawn: false);
    expect(game.cells.sublist(0, 4), [0, 0, 0, 8]);
  });

  test('2048 merges vertically', () {
    final game = Game2048.withCells([
      2,
      0,
      0,
      0,
      2,
      0,
      0,
      0,
      4,
      0,
      0,
      0,
      4,
      0,
      0,
      0,
    ]);

    game.move(Direction2048.up, spawn: false);
    expect(game.cells[0], 4);
    expect(game.cells[4], 8);
    expect(game.cells[8], 0);
  });

  test('2048 reports no move when the board cannot change', () {
    final game = Game2048.withCells([
      2,
      4,
      8,
      16,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);

    expect(game.move(Direction2048.left, spawn: false), isFalse);
  });

  test('2048 detects a locked board', () {
    final game = Game2048.withCells([
      2,
      4,
      2,
      4,
      4,
      2,
      4,
      2,
      2,
      4,
      2,
      4,
      4,
      2,
      4,
      2,
    ]);

    expect(game.hasMoves, isFalse);
  });

  test('2048 reset spawns exactly two tiles', () {
    final game = Game2048(random: Random(7));
    game.reset();

    final values = game.cells.where((value) => value != 0).toList();
    expect(values, hasLength(2));
    expect(values.every((value) => value == 2 || value == 4), isTrue);
    expect(game.score, 0);
  });

  test('2048 bot picks the only available move', () {
    const cells = [2, 4, 8, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

    expect(Game2048Bot.chooseMove(cells), Direction2048.down);
  });

  test('2048 bot returns null on a locked board', () {
    const cells = [2, 4, 2, 4, 4, 2, 4, 2, 2, 4, 2, 4, 4, 2, 4, 2];

    expect(Game2048Bot.chooseMove(cells), isNull);
  });

  test('2048 supports a 5x5 board', () {
    final game = Game2048(size: 5, target: 4096, random: Random(3));
    game.reset();

    expect(game.cells, hasLength(25));
    expect(game.cells.where((value) => value != 0), hasLength(2));

    game.cells.fillRange(0, game.cells.length, 0);
    game.cells[0] = 2;
    game.cells[1] = 2;

    expect(game.move(Direction2048.left, spawn: false), isTrue);
    expect(game.cells[0], 4);
  });

  test('2048 modes expose increasing sizes and targets', () {
    expect(Game2048Mode.mini.size, 3);
    expect(Game2048Mode.classic.size, 4);
    expect(Game2048Mode.large.size, 5);
    expect(Game2048Mode.huge.size, 6);
    expect(Game2048Mode.classic.target, 2048);
    expect(Game2048Mode.large.target, 4096);
  });
}
