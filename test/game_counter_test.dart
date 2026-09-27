import 'package:flutter_test/flutter_test.dart';

import 'package:pockito/main.dart';

void main() {
  GameScene sceneWithTwoPlayers() {
    final score = GameCounterType(id: 'score', name: 'Score');
    final mana = GameCounterType(id: 'mana', name: 'Mana');
    return GameScene(
      id: 'scene',
      name: 'Game',
      types: [score, mana],
      users: [
        GameUser(id: 'u1'),
        GameUser(id: 'u2'),
      ],
    );
  }

  test('game counter values are tracked per user and type', () {
    final scene = sceneWithTwoPlayers();

    expect(scene.valueFor('u1', 'score'), 0);
    expect(scene.valueFor('u2', 'score'), 0);

    scene.setValueFor('u1', 'score', 3);
    scene.setValueFor('u1', 'mana', 5);
    scene.setValueFor('u2', 'score', 1);

    expect(scene.valueFor('u1', 'score'), 3);
    expect(scene.valueFor('u1', 'mana'), 5);
    expect(scene.valueFor('u2', 'score'), 1);
    expect(scene.valueFor('u2', 'mana'), 0);
  });

  test('game counter records history when the value changes', () {
    final scene = sceneWithTwoPlayers();
    scene.setValueFor('u1', 'score', 2);

    scene.record(scene.users.first, scene.types.first, 2);

    expect(scene.history, hasLength(1));
    expect(scene.history.first.userId, 'u1');
    expect(scene.history.first.typeId, 'score');
    expect(scene.history.first.delta, 2);
    expect(scene.history.first.value, 2);

    scene.record(scene.users.first, scene.types.first, 0);
    expect(scene.history, hasLength(1));
  });

  test('removing a counter type discards its history and values', () {
    final scene = sceneWithTwoPlayers();
    scene.setValueFor('u1', 'score', 4);
    scene.record(scene.users.first, scene.types.first, 4);
    scene.setValueFor('u1', 'mana', 2);
    scene.record(scene.users.first, scene.types[1], 2);

    scene.removeType('score');

    expect(scene.types.map((type) => type.id), ['mana']);
    expect(scene.valueFor('u1', 'score'), 0);
    expect(scene.valueFor('u1', 'mana'), 2);
    expect(scene.history, hasLength(1));
    expect(scene.history.single.typeId, 'mana');
  });

  test('removing a player discards their values and history', () {
    final scene = sceneWithTwoPlayers();
    scene.setValueFor('u1', 'score', 4);
    scene.setValueFor('u2', 'score', 2);
    scene.record(scene.users.first, scene.types.first, 4);
    scene.record(scene.users[1], scene.types.first, 2);

    scene.removeUser('u1');

    expect(scene.users.map((user) => user.id), ['u2']);
    expect(scene.valueFor('u1', 'score'), 0);
    expect(scene.valueFor('u2', 'score'), 2);
    expect(scene.history, hasLength(1));
    expect(scene.history.single.userId, 'u2');
  });

  test('counter types keep a quick tap direction across json', () {
    final type = GameCounterType(
      id: 'score',
      name: 'Score',
      quickDirection: -1,
    );

    final restored = GameCounterType.fromJson(type.toJson());

    expect(restored.quickDirection, -1);

    final fallback = GameCounterType.fromJson({'id': 'x', 'name': 'X'});
    expect(fallback.quickDirection, 1);
  });

  test('counter types keep a default value across json', () {
    final type = GameCounterType(id: 'score', name: 'Score', defaultValue: 10);

    final restored = GameCounterType.fromJson(type.toJson());

    expect(restored.defaultValue, 10);
    expect(GameCounterType.fromJson({'id': 'x', 'name': 'X'}).defaultValue, 0);
  });

  test('unset values fall back to the counter type default', () {
    final scene = GameScene(
      id: 'scene',
      name: 'Game',
      types: [GameCounterType(id: 'hp', name: 'Health', defaultValue: 20)],
      users: [GameUser(id: 'u1')],
    );

    expect(scene.valueFor('u1', 'hp'), 20);

    scene.setValueFor('u1', 'hp', 12);
    expect(scene.valueFor('u1', 'hp'), 12);

    scene.setValueFor('u1', 'hp', 20);
    expect(scene.valueFor('u1', 'hp'), 20);
  });

  test('game scene survives a json round trip', () {
    final scene = sceneWithTwoPlayers();
    scene.setValueFor('u1', 'score', 7);
    scene.record(scene.users.first, scene.types.first, 7);

    final restored = GameScene.fromJson(scene.toJson());

    expect(restored.types.map((type) => type.id), ['score', 'mana']);
    expect(restored.users.map((user) => user.id), ['u1', 'u2']);
    expect(restored.valueFor('u1', 'score'), 7);
    expect(restored.history, hasLength(1));
    expect(restored.history.first.value, 7);
  });
}
