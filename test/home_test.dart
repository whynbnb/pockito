import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pockito/main.dart';

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

Widget homeApp(LocalPreferences preferences) =>
    VaultApp(preferences: preferences);

Future<void> pumpHome(WidgetTester tester, LocalPreferences preferences) async {
  await tester.pumpWidget(homeApp(preferences));
  await tester.pumpAndSettle();
}

Future<void> tapNav(WidgetTester tester, HomeView view) async {
  await tester.tap(find.byKey(ValueKey('home-nav-${view.name}')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows four home tabs and defaults to All', (tester) async {
    await pumpHome(tester, _MemoryPreferences(<String, String>{}));

    expect(find.byKey(const PageStorageKey('home-all')), findsOneWidget);
    expect(find.text('All tools'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-nav-recent')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-nav-favorites')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-nav-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-nav-settings')), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
  });

  testWidgets('remembers the last selected tab', (tester) async {
    final store = <String, String>{};
    await pumpHome(tester, _MemoryPreferences(store));

    await tapNav(tester, HomeView.favorites);
    expect(find.byKey(const ValueKey('home-favorites-empty')), findsOneWidget);

    await pumpHome(tester, _MemoryPreferences(store));
    expect(find.byKey(const ValueKey('home-favorites-empty')), findsOneWidget);
    expect(find.byKey(const PageStorageKey('home-all')), findsNothing);
  });

  testWidgets('favorites a tool and persists it', (tester) async {
    final store = <String, String>{};
    await pumpHome(tester, _MemoryPreferences(store));

    await tester.tap(
      find.byKey(const ValueKey('tool-favorite-password-generator')),
    );
    await tester.pumpAndSettle();

    await tapNav(tester, HomeView.favorites);
    expect(
      find.byKey(const ValueKey('tool-tile-password-generator')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-favorites-empty')), findsNothing);

    await pumpHome(tester, _MemoryPreferences(store));
    expect(
      find.byKey(const ValueKey('tool-tile-password-generator')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('tool-favorite-password-generator')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-favorites-empty')), findsOneWidget);
  });

  testWidgets('records recently opened tools and clears them', (tester) async {
    final store = <String, String>{};
    await pumpHome(tester, _MemoryPreferences(store));

    await tester.tap(find.text('Password Generator'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapNav(tester, HomeView.recent);
    expect(
      find.byKey(const ValueKey('tool-tile-password-generator')),
      findsOneWidget,
    );

    await pumpHome(tester, _MemoryPreferences(store));
    await tapNav(tester, HomeView.recent);
    expect(
      find.byKey(const ValueKey('tool-tile-password-generator')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('home-clear-recent')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-recent-empty')), findsOneWidget);
  });

  testWidgets('hides tabs, keeps one tool view and uses the settings icon', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHome(tester, _MemoryPreferences(<String, String>{}));
    await tapNav(tester, HomeView.settings);

    await tester.tap(find.byKey(const ValueKey('home-show-recent')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-nav-recent')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-show-favorites')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-nav-favorites')), findsNothing);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('home-show-all')))
          .onChanged,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('home-show-all')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('home-show-all')))
          .value,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('home-show-settings')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('home-settings-fallback')),
      findsOneWidget,
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const PageStorageKey('home-all')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-settings-fallback')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-show-settings')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-settings-fallback')), findsNothing);
    expect(find.byKey(const ValueKey('home-nav-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-nav-settings')), findsOneWidget);
  });

  test('home state persists and keeps at least one tool view', () async {
    final store = <String, String>{};
    final settings = AppSettings(preferences: _MemoryPreferences(store));
    await settings.load();

    await settings.markToolOpened('clock');
    await settings.markToolOpened('world-clock');
    await settings.markToolOpened('clock');
    expect(settings.recentToolIds, ['clock', 'world-clock']);

    await settings.toggleFavorite('password-generator');
    expect(settings.favoriteToolIds, {'password-generator'});

    await settings.setHomeViewVisible(HomeView.recent, false);
    await settings.setHomeViewVisible(HomeView.favorites, false);
    expect(settings.canHideHomeView(HomeView.all), isFalse);
    await settings.setHomeViewVisible(HomeView.all, false);
    expect(settings.isHomeViewVisible(HomeView.all), isTrue);

    await settings.setHomeTab(HomeView.all);
    await settings.setHomeViewVisible(HomeView.settings, false);
    expect(settings.isHomeViewVisible(HomeView.settings), isFalse);

    final reloaded = AppSettings(preferences: _MemoryPreferences(store));
    await reloaded.load();
    expect(reloaded.recentToolIds, ['clock', 'world-clock']);
    expect(reloaded.favoriteToolIds, {'password-generator'});
    expect(reloaded.isHomeViewVisible(HomeView.recent), isFalse);
    expect(reloaded.isHomeViewVisible(HomeView.favorites), isFalse);
    expect(reloaded.isHomeViewVisible(HomeView.all), isTrue);
    expect(reloaded.isHomeViewVisible(HomeView.settings), isFalse);
    expect(reloaded.homeTab, HomeView.all);
  });

  test('loads valid saved home state and ignores invalid values', () async {
    final settings = AppSettings(
      preferences: _MemoryPreferences({
        'home_state': jsonEncode({
          'recent': ['missing', 'clock', 'clock'],
          'favorites': ['missing', 'world-clock'],
          'hidden': ['recent', 'favorites', 'all'],
          'tab': 'settings',
        }),
      }),
    );
    await settings.load();

    expect(settings.recentToolIds, ['clock']);
    expect(settings.favoriteToolIds, {'world-clock'});
    expect(settings.isHomeViewVisible(HomeView.all), isTrue);
    expect(settings.isHomeViewVisible(HomeView.settings), isTrue);
    expect(settings.homeTab, HomeView.settings);
  });
}
