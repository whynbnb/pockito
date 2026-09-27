import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pockito/main.dart';

void main() {
  test('creates and unlocks a PIN vault', () async {
    final directory = await Directory.systemTemp.createTemp('vault');
    addTearDown(() => directory.delete(recursive: true));

    final store = VaultStore(directory);
    await store.initialize();
    expect(store.exists, isFalse);

    await store.create(type: VaultLockType.pin, secret: '1234');
    expect(store.exists, isTrue);
    expect(store.lockType, VaultLockType.pin);

    final reopened = VaultStore(directory);
    await reopened.initialize();
    expect(reopened.exists, isTrue);
    expect(reopened.lockType, VaultLockType.pin);
    expect(await reopened.unlock('9999'), isFalse);
    expect(await reopened.unlock('1234'), isTrue);
  });

  test('persists notes across a pattern unlock', () async {
    final directory = await Directory.systemTemp.createTemp('vault-notes');
    addTearDown(() => directory.delete(recursive: true));

    final store = VaultStore(directory);
    await store.initialize();
    await store.create(type: VaultLockType.pattern, secret: '0-1-2-5-8');
    store.notes.add(
      VaultNote(
        id: '1',
        title: 'Secret',
        body: 'body',
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    await store.save();

    final reopened = VaultStore(directory);
    await reopened.initialize();
    expect(reopened.lockType, VaultLockType.pattern);
    expect(await reopened.unlock('0-1-2-5-8'), isTrue);
    expect(reopened.notes, hasLength(1));
    expect(reopened.notes.first.title, 'Secret');
  });
}
