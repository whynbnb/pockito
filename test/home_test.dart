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

Widget homeApp(LocalPreferences preferences, {Key? key}) =>
    VaultApp(key: key, preferences: preferences);

Future<void> pumpHome(
  WidgetTester tester,
  LocalPreferences preferences, {
  Key? key,
}) async {
  await tester.pumpWidget(homeApp(preferences, key: key));
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
    expect(find.text('Pockito'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
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

    await pumpHome(
      tester,
      _MemoryPreferences(store),
      key: const ValueKey('reloaded'),
    );
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

    await pumpHome(
      tester,
      _MemoryPreferences(store),
      key: const ValueKey('reloaded'),
    );
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
    tester.view.physicalSize = const Size(800, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

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

    await pumpHome(
      tester,
      _MemoryPreferences(store),
      key: const ValueKey('reloaded'),
    );
    await tapNav(tester, HomeView.recent);
    expect(
      find.byKey(const ValueKey('tool-tile-password-generator')),
      findsOneWidget,
    );

    await tapNav(tester, HomeView.settings);
    final clearRecent = find.byKey(const ValueKey('settings-clear-recent'));
    await tester.ensureVisible(clearRecent);
    await tester.pumpAndSettle();
    await tester.tap(clearRecent);
    await tester.pumpAndSettle();

    await tapNav(tester, HomeView.recent);
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

    final fallback = find.byKey(const ValueKey('home-settings-fallback'));
    expect(fallback, findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const PageStorageKey('home-all')), findsOneWidget);
    final fallbackRect = tester.getRect(fallback);
    final searchRect = tester.getRect(
      find.byKey(const ValueKey('home-search-all')),
    );
    expect(fallbackRect.left, greaterThan(searchRect.right));
    expect(fallbackRect.center.dy, closeTo(searchRect.center.dy, 4));

    await tester.tap(find.byKey(const ValueKey('home-settings-fallback')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-show-settings')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-settings-fallback')), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('home-nav-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-nav-settings')), findsOneWidget);
  });

  testWidgets('searches tools in the All view and clears the query', (
    tester,
  ) async {
    await pumpHome(tester, _MemoryPreferences(<String, String>{}));

    final search = find.byKey(const ValueKey('home-search-all'));
    expect(search, findsOneWidget);

    await tester.enterText(search, 'clock');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('tool-tile-clock')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-tile-world-clock')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tool-tile-password-generator')),
      findsNothing,
    );
    expect(find.text('2 results'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-search-clear-all')), findsOneWidget);

    await tester.enterText(search, '时钟');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool-tile-clock')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-tile-world-clock')), findsOneWidget);
    expect(find.text('2 results'), findsOneWidget);

    await tester.enterText(search, 'matching nothing');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-search-empty-all')), findsOneWidget);
    expect(find.text('0 results'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-search-clear-all')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tool-tile-password-generator')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-search-empty-all')), findsNothing);
  });

  testWidgets('finds tools by tag', (tester) async {
    await pumpHome(tester, _MemoryPreferences(<String, String>{}));

    final search = find.byKey(const ValueKey('home-search-all'));
    await tester.enterText(search, 'Board games');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('tool-tile-game-counter')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tool-tile-clock')), findsNothing);
    expect(find.text('1 result'), findsOneWidget);

    await tester.enterText(search, '音频');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('tool-tile-tone-generator')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tool-tile-speaker-cleaner')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tool-tile-clock')), findsNothing);
  });

  testWidgets('expands the mobile search field on focus', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHome(tester, _MemoryPreferences(<String, String>{}));

    final search = find.byKey(const ValueKey('home-search-all'));
    final before = tester.getSize(search).width;
    expect(before, lessThan(220));

    await tester.tap(search);
    await tester.pumpAndSettle();

    final after = tester.getSize(search).width;
    expect(after, greaterThan(before));
    expect(after, lessThan(260));
    final titleRect = tester.getRect(find.text('Pockito'));
    final fieldRect = tester.getRect(search);
    expect(titleRect.right, lessThanOrEqualTo(fieldRect.left));
  });

  testWidgets('searches recent and favorites independently', (tester) async {
    final store = <String, String>{
      'home_state': jsonEncode({
        'recent': ['world-clock', 'password-generator'],
        'favorites': ['clock', 'password-generator'],
        'hidden': <String>[],
        'tab': 'all',
      }),
    };
    await pumpHome(tester, _MemoryPreferences(store));

    await tapNav(tester, HomeView.favorites);
    final favoriteSearch = find.byKey(const ValueKey('home-search-favorites'));
    expect(favoriteSearch, findsOneWidget);
    await tester.enterText(favoriteSearch, 'clock');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool-tile-clock')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tool-tile-password-generator')),
      findsNothing,
    );
    expect(find.text('1 result'), findsOneWidget);

    await tapNav(tester, HomeView.recent);
    final recentSearch = find.byKey(const ValueKey('home-search-recent'));
    expect(recentSearch, findsOneWidget);
    await tester.enterText(recentSearch, 'world');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tool-tile-world-clock')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tool-tile-password-generator')),
      findsNothing,
    );

    await tapNav(tester, HomeView.settings);
    expect(find.byType(SettingsView), findsOneWidget);
    expect(find.byKey(const ValueKey('home-search-settings')), findsNothing);
  });

  testWidgets('uses a navigation rail and a card grid on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHome(tester, _MemoryPreferences(<String, String>{}));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey('home-search-all')), findsOneWidget);

    final first = find.byKey(const ValueKey('tool-tile-password-generator'));
    final second = find.byKey(const ValueKey('tool-tile-counter'));
    final third = find.byKey(const ValueKey('tool-tile-game-counter'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(third, findsOneWidget);

    final firstTop = tester.getTopLeft(first);
    final secondTop = tester.getTopLeft(second);
    final thirdTop = tester.getTopLeft(third);
    expect(firstTop.dy, secondTop.dy);
    expect(firstTop.dx, lessThan(secondTop.dx));
    expect(thirdTop.dy, greaterThan(firstTop.dy));
    expect(tester.getSize(first).width, greaterThan(300));
    expect(tester.getSize(first).height, tester.getSize(second).height);

    final gameCounter = find.byKey(const ValueKey('tool-card-game-counter'));
    final basexx = find.byKey(const ValueKey('tool-card-basexx'));
    expect(tester.getSize(gameCounter).height, tester.getSize(basexx).height);
    final firstCard = find.byKey(
      const ValueKey('tool-card-password-generator'),
    );
    final secondCard = find.byKey(const ValueKey('tool-card-counter'));
    expect(tester.getSize(firstCard).height, tester.getSize(secondCard).height);

    await tapNav(tester, HomeView.settings);
    expect(find.byType(SettingsView), findsOneWidget);
  });

  testWidgets('caps tool subtitles at two lines', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHome(tester, _MemoryPreferences(<String, String>{}));
    final subtitle = toolInfoById('tone-generator')!.englishSubtitle;
    final text = tester.widget<Text>(find.text(subtitle));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('keeps breathing room under two-line descriptions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHome(tester, _MemoryPreferences(<String, String>{}));
    final subtitle = toolInfoById('basexx')!.englishSubtitle;
    final text = find.text(subtitle);
    final card = find.byKey(const ValueKey('tool-card-basexx'));
    final padding = tester.widget<Padding>(
      find.ancestor(of: text, matching: find.byType(Padding)).first,
    );
    expect(padding.padding, const EdgeInsets.fromLTRB(18, 14, 10, 14));

    final textRect = tester.getRect(text);
    final cardRect = tester.getRect(card);
    expect(cardRect.bottom - textRect.bottom, greaterThanOrEqualTo(12));
  });

  testWidgets('changes the app accent from settings', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = <String, String>{};
    await pumpHome(tester, _MemoryPreferences(store));
    await tapNav(tester, HomeView.settings);

    final blue = themeAccentPresets.firstWhere((preset) => preset.id == 'blue');
    final swatch = find.byKey(const ValueKey('settings-accent-blue'));
    await tester.ensureVisible(swatch);
    await tester.pumpAndSettle();

    final before = Theme.of(tester.element(find.byType(SettingsView)))
        .colorScheme
        .primary;
    await tester.tap(swatch);
    await tester.pumpAndSettle();
    final after = Theme.of(tester.element(find.byType(SettingsView)))
        .colorScheme
        .primary;

    expect(after, isNot(before));
    expect(int.tryParse(store['ui_accent']!), blue.color);
    expect(store['ui_dynamic'], '0');
    expect(find.byKey(const ValueKey('settings-material-you')), findsNothing);
  });

  test('persists theme accent and dynamic color', () async {
    final store = <String, String>{};
    final settings = AppSettings(preferences: _MemoryPreferences(store));
    await settings.load();
    expect(settings.accentColor, defaultThemeAccent);
    expect(settings.useDynamicColor, isFalse);

    final blue = themeAccentPresets.firstWhere((preset) => preset.id == 'blue');
    await settings.setAccentColor(blue.color);
    expect(settings.accentColor, blue.color);
    await settings.setUseDynamicColor(true);
    expect(settings.useDynamicColor, isTrue);

    final reloaded = AppSettings(preferences: _MemoryPreferences(store));
    await reloaded.load();
    expect(reloaded.accentColor, blue.color);
    expect(reloaded.useDynamicColor, isTrue);

    await reloaded.setAccentColor(themeAccentPresets.first.color);
    expect(reloaded.useDynamicColor, isFalse);
  });

  testWidgets('minimal mode merges favorites and recent without tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = <String, String>{
      'home_state': jsonEncode({
        'recent': ['tone-generator', 'clock'],
        'favorites': ['clock', 'world-clock'],
        'hidden': <String>[],
        'tab': 'all',
        'remember': true,
        'minimal': true,
      }),
    };
    await pumpHome(tester, _MemoryPreferences(store));

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const PageStorageKey('home-minimal')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-nav-all')), findsNothing);
    expect(find.byKey(const ValueKey('home-nav-recent')), findsNothing);
    expect(find.text('Pockito'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);

    expect(find.byKey(const ValueKey('tool-tile-clock')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-tile-world-clock')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tool-tile-tone-generator')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('tool-tile-password-generator')),
      findsNothing,
    );
  });

  testWidgets('minimal search finds tools outside favorites and recent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = <String, String>{
      'home_state': jsonEncode({
        'recent': ['clock'],
        'favorites': ['world-clock'],
        'hidden': <String>[],
        'tab': 'all',
        'minimal': true,
      }),
    };
    await pumpHome(tester, _MemoryPreferences(store));

    final search = find.byKey(const ValueKey('home-search-minimal'));
    await tester.enterText(search, 'password');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('tool-tile-password-generator')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tool-tile-clock')), findsNothing);
    expect(find.text('1 result'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-search-clear-minimal')));
    await tester.pumpAndSettle();
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);
  });

  testWidgets('minimal mode shows an empty state without history', (
    tester,
  ) async {
    final store = <String, String>{
      'home_state': jsonEncode({
        'recent': <String>[],
        'favorites': <String>[],
        'hidden': <String>[],
        'tab': 'all',
        'minimal': true,
      }),
    };
    await pumpHome(tester, _MemoryPreferences(store));

    expect(find.byKey(const ValueKey('home-minimal-empty')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey('home-search-minimal')), findsOneWidget);
  });

  testWidgets('toggles minimal mode from settings', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = <String, String>{};
    await pumpHome(tester, _MemoryPreferences(store));
    await tapNav(tester, HomeView.settings);

    final toggle = find.byKey(const ValueKey('home-minimal-mode'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const PageStorageKey('home-minimal')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('home-settings-fallback')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('home-remember-tab')), findsNothing);

    final decoded = jsonDecode(store['home_state']!) as Map<String, dynamic>;
    expect(decoded['minimal'], isTrue);

    await tester.tap(find.byKey(const ValueKey('home-settings-fallback')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    final screenToggle = find.byKey(const ValueKey('home-minimal-mode'));
    await tester.ensureVisible(screenToggle);
    await tester.tap(screenToggle);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
  });

  test('minimal mode persists and defaults off', () async {
    final store = <String, String>{};
    final settings = AppSettings(preferences: _MemoryPreferences(store));
    await settings.load();
    expect(settings.minimalMode, isFalse);

    await settings.setMinimalMode(true);
    final reloaded = AppSettings(preferences: _MemoryPreferences(store));
    await reloaded.load();
    expect(reloaded.minimalMode, isTrue);
  });

  testWidgets('can disable remembering the last view', (tester) async {
    tester.view.physicalSize = const Size(800, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = <String, String>{};
    await pumpHome(tester, _MemoryPreferences(store));
    await tapNav(tester, HomeView.settings);

    final toggle = find.byKey(const ValueKey('home-remember-tab'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tapNav(tester, HomeView.favorites);

    await pumpHome(
      tester,
      _MemoryPreferences(store),
      key: const ValueKey('reloaded'),
    );
    expect(find.byKey(const PageStorageKey('home-all')), findsOneWidget);
    expect(find.byKey(const PageStorageKey('home-favorites')), findsNothing);
  });

  test('can stop restoring the last home tab', () async {
    final store = <String, String>{};
    final settings = AppSettings(preferences: _MemoryPreferences(store));
    await settings.load();
    await settings.setHomeTab(HomeView.favorites);
    await settings.setRememberHomeTab(false);

    final reloaded = AppSettings(preferences: _MemoryPreferences(store));
    await reloaded.load();
    expect(reloaded.rememberHomeTab, isFalse);
    expect(reloaded.homeTab, HomeView.all);
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
