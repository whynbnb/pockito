import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pinyin/pinyin.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    try {
      await windowManager.ensureInitialized();
    } catch (_) {
      // The clock still works inside the window if the plugin is unavailable.
    }
  }
  FlutterError.onError = (details) {
    final exception = details.exception;
    if (exception is AssertionError &&
        exception.toString().contains(
          'Attempted to send a key down event when no keys are in keysPressed',
        )) {
      return;
    }
    FlutterError.presentError(details);
  };
  runApp(const VaultApp());
}

String tr(BuildContext context, String english, String chinese) =>
    AppSettings.of(context).localeMode == LocaleMode.chinese ||
        (AppSettings.of(context).localeMode == LocaleMode.system &&
            Localizations.localeOf(context).languageCode == 'zh')
    ? chinese
    : english;

enum LocaleMode { english, chinese, system }

const int defaultThemeAccent = 0xff007c72;

class ThemeAccentPreset {
  const ThemeAccentPreset(
    this.id,
    this.englishName,
    this.chineseName,
    this.color,
  );

  final String id;
  final String englishName;
  final String chineseName;
  final int color;
}

const themeAccentPresets = <ThemeAccentPreset>[
  ThemeAccentPreset('teal', 'Teal', '青色', 0xff007c72),
  ThemeAccentPreset('blue', 'Blue', '蓝色', 0xff1565c0),
  ThemeAccentPreset('indigo', 'Indigo', '靛蓝', 0xff3949ab),
  ThemeAccentPreset('purple', 'Purple', '紫色', 0xff7b1fa2),
  ThemeAccentPreset('pink', 'Pink', '粉色', 0xffc2185b),
  ThemeAccentPreset('red', 'Red', '红色', 0xffc62828),
  ThemeAccentPreset('orange', 'Orange', '橙色', 0xffe65100),
  ThemeAccentPreset('amber', 'Amber', '琥珀', 0xfff9a825),
  ThemeAccentPreset('green', 'Green', '绿色', 0xff2e7d32),
  ThemeAccentPreset('cyan', 'Cyan', '青蓝', 0xff00838f),
  ThemeAccentPreset('brown', 'Brown', '棕色', 0xff5d4037),
  ThemeAccentPreset('graphite', 'Graphite', '石墨', 0xff455a64),
];

class LocalPreferences {
  LocalPreferences([this._directory]) : _fileName = _defaultFileName;

  LocalPreferences.forFile(this._fileName, [this._directory]);

  static const _defaultFileName = 'tool_prefs.json';
  final Directory? _directory;
  final String _fileName;
  File? _file;
  Map<String, dynamic>? _cache;

  Future<File> _resolveFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final directory = _directory ?? await getApplicationSupportDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$_fileName');
    _file = file;
    return file;
  }

  Future<Map<String, dynamic>> _readAll() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return _cache = {};
      final raw = await file.readAsString();
      final decoded = raw.trim().isEmpty ? null : jsonDecode(raw);
      return _cache = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return _cache = {};
    }
  }

  Future<String?> getString(String key) async {
    final value = (await _readAll())[key];
    return value is String ? value : null;
  }

  Future<void> setString(String key, String value) async {
    final all = await _readAll();
    all[key] = value;
    try {
      final file = await _resolveFile();
      await file.writeAsString(jsonEncode(all), flush: true);
    } catch (_) {}
  }
}

enum HomeView {
  recent,
  favorites,
  all,
  settings;

  static const core = <HomeView>[
    HomeView.recent,
    HomeView.favorites,
    HomeView.all,
  ];
}

extension HomeViewDetails on HomeView {
  String get englishName => switch (this) {
    HomeView.recent => 'Recent',
    HomeView.favorites => 'Favorites',
    HomeView.all => 'All',
    HomeView.settings => 'Settings',
  };

  String get chineseName => switch (this) {
    HomeView.recent => '最近',
    HomeView.favorites => '收藏',
    HomeView.all => '全部',
    HomeView.settings => '设置',
  };

  String get englishSubtitle => switch (this) {
    HomeView.recent => 'Recently opened tools',
    HomeView.favorites => 'Tools you starred',
    HomeView.all => 'Every tool in Pockito',
    HomeView.settings => 'Appearance, language and home tabs',
  };

  String get chineseSubtitle => switch (this) {
    HomeView.recent => '最近打开的工具',
    HomeView.favorites => '已收藏的工具',
    HomeView.all => '应用中的全部工具',
    HomeView.settings => '外观、语言与首页界面',
  };

  IconData get icon => switch (this) {
    HomeView.recent => Icons.history,
    HomeView.favorites => Icons.star_border,
    HomeView.all => Icons.grid_view_outlined,
    HomeView.settings => Icons.tune,
  };

  IconData get selectedIcon => switch (this) {
    HomeView.recent => Icons.history,
    HomeView.favorites => Icons.star,
    HomeView.all => Icons.grid_view_rounded,
    HomeView.settings => Icons.tune,
  };
}

class AppSettings extends ChangeNotifier {
  AppSettings({LocalPreferences? preferences})
    : _preferences = preferences ?? LocalPreferences();

  static const int maxRecentTools = 20;
  final LocalPreferences _preferences;
  ThemeMode themeMode = ThemeMode.system;
  LocaleMode localeMode = LocaleMode.system;
  int accentColor = defaultThemeAccent;
  bool useDynamicColor = false;
  List<String> recentToolIds = [];
  Set<String> favoriteToolIds = {};
  Set<HomeView> hiddenHomeViews = {};
  HomeView homeTab = HomeView.all;
  bool rememberHomeTab = true;

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SettingsScope>()!.settings;

  List<HomeView> get visibleHomeViews {
    final views = <HomeView>[
      for (final view in HomeView.values)
        if (!hiddenHomeViews.contains(view)) view,
    ];
    return views.isEmpty ? const [HomeView.all] : views;
  }

  bool isHomeViewVisible(HomeView view) => !hiddenHomeViews.contains(view);

  HomeView get fallbackHomeView {
    for (final view in HomeView.core) {
      if (isHomeViewVisible(view)) return view;
    }
    return HomeView.all;
  }

  bool canHideHomeView(HomeView view) {
    if (view == HomeView.settings) return true;
    if (hiddenHomeViews.contains(view)) return true;
    return HomeView.core.where(isHomeViewVisible).length > 1;
  }

  Future<void> load() async {
    try {
      final theme = await _preferences.getString('ui_theme');
      final language = await _preferences.getString('ui_language');
      final accent = await _preferences.getString('ui_accent');
      final dynamicColor = await _preferences.getString('ui_dynamic');
      if (theme != null) {
        themeMode = switch (theme) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        };
      }
      if (language != null) {
        localeMode = switch (language) {
          'zh' => LocaleMode.chinese,
          'en' => LocaleMode.english,
          _ => LocaleMode.system,
        };
      }
      if (accent != null) {
        final value = int.tryParse(accent);
        if (value != null && value >= 0 && value <= 0xffffffff) {
          accentColor = value;
        }
      }
      if (dynamicColor != null) {
        useDynamicColor = dynamicColor == '1';
      }
    } catch (_) {
      // Keep defaults when local storage is unavailable.
    }
    try {
      final raw = await _preferences.getString('home_state');
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final recent = map['recent'];
          if (recent is List) {
            final seen = <String>{};
            for (final value in recent) {
              if (value is String &&
                  toolInfoById(value) != null &&
                  seen.add(value)) {
                recentToolIds.add(value);
                if (recentToolIds.length >= maxRecentTools) break;
              }
            }
          }
          final favorites = map['favorites'];
          if (favorites is List) {
            for (final value in favorites) {
              if (value is String && toolInfoById(value) != null) {
                favoriteToolIds.add(value);
              }
            }
          }
          final hidden = map['hidden'];
          if (hidden is List) {
            for (final value in hidden) {
              final view = _homeViewFromName(value);
              if (view != null) hiddenHomeViews.add(view);
            }
          }
          final tab = _homeViewFromName(map['tab']);
          if (tab != null) homeTab = tab;
          if (map['remember'] case final bool remember) {
            rememberHomeTab = remember;
          }
        }
      }
    } catch (_) {
      // Keep the defaults when the stored home state cannot be read.
    }
    if (HomeView.core.every(hiddenHomeViews.contains)) {
      hiddenHomeViews.remove(HomeView.all);
    }
    if (!rememberHomeTab) homeTab = HomeView.all;
    if (!isHomeViewVisible(homeTab)) homeTab = fallbackHomeView;
    notifyListeners();
  }

  static HomeView? _homeViewFromName(dynamic value) {
    if (value is! String) return null;
    for (final view in HomeView.values) {
      if (view.name == value) return view;
    }
    return null;
  }

  Future<void> _saveHomeState() async {
    try {
      await _preferences.setString(
        'home_state',
        jsonEncode({
          'recent': recentToolIds,
          'favorites': favoriteToolIds.toList(),
          'hidden': [for (final view in hiddenHomeViews) view.name],
          'tab': homeTab.name,
          'remember': rememberHomeTab,
        }),
      );
    } catch (_) {}
  }

  Future<void> markToolOpened(String id) async {
    if (toolInfoById(id) == null) return;
    recentToolIds.remove(id);
    recentToolIds.insert(0, id);
    if (recentToolIds.length > maxRecentTools) {
      recentToolIds = recentToolIds.sublist(0, maxRecentTools);
    }
    notifyListeners();
    await _saveHomeState();
  }

  Future<void> toggleFavorite(String id) async {
    if (toolInfoById(id) == null) return;
    if (!favoriteToolIds.add(id)) favoriteToolIds.remove(id);
    notifyListeners();
    await _saveHomeState();
  }

  Future<void> setHomeTab(HomeView view) async {
    if (!isHomeViewVisible(view) || homeTab == view) return;
    homeTab = view;
    notifyListeners();
    await _saveHomeState();
  }

  Future<void> setRememberHomeTab(bool value) async {
    if (rememberHomeTab == value) return;
    rememberHomeTab = value;
    notifyListeners();
    await _saveHomeState();
  }

  Future<void> setHomeViewVisible(HomeView view, bool visible) async {
    if (visible) {
      if (!hiddenHomeViews.remove(view)) return;
    } else {
      if (!canHideHomeView(view)) return;
      if (!hiddenHomeViews.add(view)) return;
    }
    if (!isHomeViewVisible(homeTab)) homeTab = fallbackHomeView;
    notifyListeners();
    await _saveHomeState();
  }

  Future<void> clearRecent() async {
    if (recentToolIds.isEmpty) return;
    recentToolIds.clear();
    notifyListeners();
    await _saveHomeState();
  }

  Future<void> clearFavorites() async {
    if (favoriteToolIds.isEmpty) return;
    favoriteToolIds.clear();
    notifyListeners();
    await _saveHomeState();
  }

  Future<void> setAccentColor(int color) async {
    accentColor = color & 0xffffffff;
    useDynamicColor = false;
    notifyListeners();
    await _saveThemeColor();
  }

  Future<void> setUseDynamicColor(bool value) async {
    useDynamicColor = value;
    notifyListeners();
    await _saveThemeColor();
  }

  Future<void> _saveThemeColor() async {
    try {
      await _preferences.setString('ui_accent', accentColor.toString());
      await _preferences.setString('ui_dynamic', useDynamicColor ? '1' : '0');
    } catch (_) {}
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    try {
      await _preferences.setString('ui_theme', switch (mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
      });
    } catch (_) {}
  }

  Future<void> setLocaleMode(LocaleMode mode) async {
    localeMode = mode;
    notifyListeners();
    try {
      await _preferences.setString('ui_language', switch (mode) {
        LocaleMode.english => 'en',
        LocaleMode.chinese => 'zh',
        LocaleMode.system => 'system',
      });
    } catch (_) {}
  }
}

class _SettingsScope extends InheritedNotifier<AppSettings> {
  const _SettingsScope({required AppSettings settings, required super.child})
    : settings = settings,
      super(notifier: settings);

  final AppSettings settings;
}

class VaultApp extends StatefulWidget {
  const VaultApp({super.key, this.home = const HomeScreen(), this.preferences});

  final Widget home;
  final LocalPreferences? preferences;

  @override
  State<VaultApp> createState() => _VaultAppState();
}

class _VaultAppState extends State<VaultApp> {
  late final AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = AppSettings(preferences: widget.preferences);
    unawaited(_settings.load());
  }

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SettingsScope(
    settings: _settings,
    child: AnimatedBuilder(
      animation: _settings,
      builder: (context, _) => DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) {
          final useDynamic =
              _settings.useDynamicColor &&
              Platform.isAndroid &&
              lightDynamic != null &&
              darkDynamic != null;
          final accent = Color(_settings.accentColor);
          final lightScheme = useDynamic
              ? lightDynamic
              : ColorScheme.fromSeed(seedColor: accent);
          final darkSeed = _settings.accentColor == defaultThemeAccent
              ? const Color(0xff54c7bb)
              : accent;
          final darkScheme = useDynamic
              ? darkDynamic
              : ColorScheme.fromSeed(
                  seedColor: darkSeed,
                  brightness: Brightness.dark,
                );
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Pockito',
            themeMode: _settings.themeMode,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('zh')],
            locale: switch (_settings.localeMode) {
              LocaleMode.english => const Locale('en'),
              LocaleMode.chinese => const Locale('zh'),
              LocaleMode.system => null,
            },
            theme: ThemeData(colorScheme: lightScheme, useMaterial3: true),
            darkTheme: ThemeData(colorScheme: darkScheme, useMaterial3: true),
            home: widget.home,
          );
        },
      ),
    ),
  );
}

Future<void> showSettings(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(context, 'Appearance', '外观设置'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const _AppearanceControls(showLabels: true),
          ],
        ),
      ),
    ),
  ),
);

class ToolCredit {
  const ToolCredit({
    required this.project,
    required this.author,
    required this.license,
    required this.url,
    this.englishDescription = '',
    this.chineseDescription = '',
  });

  final String project;
  final String author;
  final String license;
  final String url;
  final String englishDescription;
  final String chineseDescription;
}

class ToolInfo {
  const ToolInfo({
    required this.id,
    required this.icon,
    required this.englishTitle,
    required this.chineseTitle,
    required this.englishSubtitle,
    required this.chineseSubtitle,
    this.credits = const [],
    this.englishNote = '',
    this.chineseNote = '',
  });

  final String id;
  final IconData icon;
  final String englishTitle;
  final String chineseTitle;
  final String englishSubtitle;
  final String chineseSubtitle;
  final List<ToolCredit> credits;
  final String englishNote;
  final String chineseNote;

  bool get hasAcknowledgements => credits.isNotEmpty;
}

const toolInfos = <ToolInfo>[
  ToolInfo(
    id: 'password-generator',
    icon: Icons.password_outlined,
    englishTitle: 'Password Generator',
    chineseTitle: '密码生成器',
    englishSubtitle: 'Create strong passwords with custom filters and seeds.',
    chineseSubtitle: '使用自定义筛选和种子生成强密码。',
    credits: [
      ToolCredit(
        project: 'Password Generator',
        author: 'Vectura Games',
        license: 'Apache License 2.0',
        url: 'https://gitlab.com/vecturagames/passwordgenerator',
      ),
    ],
  ),
  ToolInfo(
    id: 'counter',
    icon: Icons.exposure_plus_1_outlined,
    englishTitle: '+1 Counter',
    chineseTitle: '+1 计数器',
    englishSubtitle: 'Count custom events with a single tap.',
    chineseSubtitle: '轻点即可统计自定义事件。',
    credits: [
      ToolCredit(
        project: 'Counters',
        author: 'Neïl Rahmouni',
        license: 'GNU Affero General Public License v3.0',
        url: 'https://gitlab.com/neil3000/counters',
      ),
    ],
  ),
  ToolInfo(
    id: 'game-counter',
    icon: Icons.sports_esports_outlined,
    englishTitle: 'Game Counter',
    chineseTitle: '游戏计数器',
    englishSubtitle: 'Place custom counters for board games and parties.',
    chineseSubtitle: '为桌游和聚会摆放自定义计数器面板。',
    credits: [
      ToolCredit(
        project: 'gamecounter',
        author: 'multun',
        license: 'GNU General Public License v3.0',
        url: 'https://github.com/multun/gamecounter',
      ),
    ],
  ),
  ToolInfo(
    id: 'basexx',
    icon: Icons.transform,
    englishTitle: 'Basexx',
    chineseTitle: 'Base 编解码',
    englishSubtitle: 'Encode and decode Base16, Base32, Base58 and Base64.',
    chineseSubtitle: '在 Base16、Base32、Base58 和 Base64 之间编解码。',
  ),
  ToolInfo(
    id: '2048',
    icon: Icons.grid_view_rounded,
    englishTitle: '2048',
    chineseTitle: '2048',
    englishSubtitle: 'Slide the tiles and merge them to reach 2048.',
    chineseSubtitle: '滑动方块并合并，合成 2048。',
  ),
  ToolInfo(
    id: 'tic-tac-toe',
    icon: Icons.grid_3x3,
    englishTitle: 'Tic-Tac-Toe',
    chineseTitle: '井字棋',
    englishSubtitle: 'Play against the bot and customize your marks.',
    chineseSubtitle: '与电脑对战，并可自定义符号。',
    credits: [
      ToolCredit(
        project: 'Dooz',
        author: 'yamin8000',
        license: 'GNU General Public License v3.0',
        url: 'https://github.com/yamin8000/Dooz',
      ),
    ],
  ),
  ToolInfo(
    id: 'flashlight',
    icon: Icons.flashlight_on_outlined,
    englishTitle: 'Flashlight',
    chineseTitle: '手电筒',
    englishSubtitle: 'Torch, brightness, SOS, blinking and Morse code.',
    chineseSubtitle: '手电筒、亮度、SOS、闪烁与摩尔斯电码。',
    credits: [
      ToolCredit(
        project: 'FlashDim',
        author: 'cyb3rko',
        license: 'Apache License 2.0',
        url: 'https://github.com/cyb3rko/flashdim',
      ),
    ],
    englishNote: 'Requires a device with a camera flash. Desktop platforms fall back to Morse code only.',
    chineseNote: '需要带闪光灯的设备；桌面平台仅保留摩尔斯电码功能。',
  ),
  ToolInfo(
    id: 'vibrator',
    icon: Icons.vibration,
    englishTitle: 'Vibrator',
    chineseTitle: '震动器',
    englishSubtitle: 'Play built-in or custom vibration patterns.',
    chineseSubtitle: '按内置或自定义模式震动。',
    credits: [
      ToolCredit(
        project: 'Vibrator',
        author: 'xiaofeidev',
        license: 'Apache License 2.0',
        url: 'https://github.com/xiaofeidev/Vibrator',
      ),
    ],
    englishNote: 'Requires a device with a vibration motor. Desktop platforms have no vibration hardware.',
    chineseNote: '需要带震动马达的设备；桌面平台没有震动硬件。',
  ),
  ToolInfo(
    id: 'tone-generator',
    icon: Icons.graphic_eq,
    englishTitle: 'Frequency Generator',
    chineseTitle: '频率发生器',
    englishSubtitle:
        'Play pure tones with custom frequencies, channels, layers and sweeps.',
    chineseSubtitle: '播放自定义频率、声道、叠加层与扫频的纯音。',
    credits: [
      ToolCredit(
        project: 'MotionEaseTune',
        author: 'BHznJNs',
        license: 'GNU General Public License v3.0',
        url: 'https://github.com/BHznJNs/MotionEaseTune',
        englishDescription:
            'The 100 Hz motion-sickness note in the Frequency Generator is '
            'inspired by the open-source MotionEaseTune by BHznJNs.',
        chineseDescription:
            '频率发生器中的 100 Hz 缓解晕车说明灵感来自 BHznJNs 的开源项目 '
            'MotionEaseTune。',
      ),
    ],
  ),
  ToolInfo(
    id: 'speaker-cleaner',
    icon: Icons.speaker_outlined,
    englishTitle: 'Speaker Cleaner',
    chineseTitle: '扬声器排水',
    englishSubtitle:
        'Pulse low tones and vibration to shake water out of the speaker.',
    chineseSubtitle: '用低频脉冲与震动把扬声器里的水震出来。',
  ),
  ToolInfo(
    id: 'clock',
    icon: Icons.access_time,
    englishTitle: 'Clock',
    chineseTitle: '时钟',
    englishSubtitle: 'Analog, flip, binary, big-digit and 8-segment clocks with a wake lock.',
    chineseSubtitle: '模拟、翻页、二进制、超大数字与 8 段码时钟，可保持屏幕常亮。',
  ),
  ToolInfo(
    id: 'world-clock',
    icon: Icons.public,
    englishTitle: 'World Clock',
    chineseTitle: '世界时钟',
    englishSubtitle:
        'A mechanical flip board for multiple timezones and city signs.',
    chineseSubtitle: '机场翻页牌风格的世界时钟，可添加多个时区与英文城市牌。',
  ),
];

ToolInfo? toolInfoById(String id) {
  for (final tool in toolInfos) {
    if (tool.id == id) return tool;
  }
  return null;
}

class ToolText {
  const ToolText(this.english, this.chinese);

  final String english;
  final String chinese;

  String resolve(BuildContext context) => tr(context, english, chinese);
}

enum ToolPlatform { android, ios, macos, windows, linux }

enum ToolPlatformSupport { full, partial, none }

class ToolPlatformStatus {
  const ToolPlatformStatus(this.platform, this.support);

  final ToolPlatform platform;
  final ToolPlatformSupport support;
}

const _allPlatforms = <ToolPlatformStatus>[
  ToolPlatformStatus(ToolPlatform.android, ToolPlatformSupport.full),
  ToolPlatformStatus(ToolPlatform.ios, ToolPlatformSupport.full),
  ToolPlatformStatus(ToolPlatform.macos, ToolPlatformSupport.full),
  ToolPlatformStatus(ToolPlatform.windows, ToolPlatformSupport.full),
  ToolPlatformStatus(ToolPlatform.linux, ToolPlatformSupport.full),
];

const _desktopPartialPlatforms = <ToolPlatformStatus>[
  ToolPlatformStatus(ToolPlatform.android, ToolPlatformSupport.full),
  ToolPlatformStatus(ToolPlatform.ios, ToolPlatformSupport.full),
  ToolPlatformStatus(ToolPlatform.macos, ToolPlatformSupport.partial),
  ToolPlatformStatus(ToolPlatform.windows, ToolPlatformSupport.partial),
  ToolPlatformStatus(ToolPlatform.linux, ToolPlatformSupport.partial),
];

const _mobileOnlyPlatforms = <ToolPlatformStatus>[
  ToolPlatformStatus(ToolPlatform.android, ToolPlatformSupport.full),
  ToolPlatformStatus(ToolPlatform.ios, ToolPlatformSupport.full),
  ToolPlatformStatus(ToolPlatform.macos, ToolPlatformSupport.none),
  ToolPlatformStatus(ToolPlatform.windows, ToolPlatformSupport.none),
  ToolPlatformStatus(ToolPlatform.linux, ToolPlatformSupport.none),
];

class ToolDetails {
  const ToolDetails({
    required this.tags,
    required this.scope,
    required this.limitations,
    required this.released,
    required this.updated,
    this.platforms = _allPlatforms,
    this.version = '1.0',
  });

  final List<ToolText> tags;
  final ToolText scope;
  final List<ToolText> limitations;
  final List<ToolPlatformStatus> platforms;
  final String version;
  final String released;
  final String updated;
}

const toolDetailsById = <String, ToolDetails>{
  'password-generator': ToolDetails(
    tags: [
      ToolText('Security', '安全'),
      ToolText('Generator', '生成器'),
      ToolText('Offline', '离线'),
      ToolText('Privacy', '隐私'),
    ],
    scope: ToolText(
      'Generate passwords for websites, apps and local accounts. Everything '
          'runs on the device.',
      '为网站、应用和本地账号生成密码，全部在设备本地完成。',
    ),
    limitations: [
      ToolText(
        'Generated passwords stay in the app until you copy them.',
        '生成的密码只保存在应用内，需要手动复制。',
      ),
      ToolText(
        'Strength depends on the chosen length and character filters.',
        '密码强度取决于所选长度与字符过滤条件。',
      ),
      ToolText(
        'Uses the platform random source; a compromised device is out of scope.',
        '使用系统随机源，无法防御已被攻破的设备。',
      ),
    ],
    released: '2026-09-05',
    updated: '2026-09-05',
  ),
  'counter': ToolDetails(
    tags: [
      ToolText('Utility', '实用'),
      ToolText('Tracking', '记录'),
      ToolText('Offline', '离线'),
    ],
    scope: ToolText(
      'Tally repeated events such as habits, visitors, repetitions or stock '
          'counts with a single tap.',
      '统计习惯、访客、重复次数或库存等需要随手加一的事件。',
    ),
    limitations: [
      ToolText(
        'Counters and their history stay on this device.',
        '计数器与记录只保存在本机。',
      ),
      ToolText(
        'History records are kept per counter and can be cleared at any time.',
        '每个计数器的记录单独保存，可随时清除。',
      ),
      ToolText('There is no cloud sync between devices.', '不支持多设备云同步。'),
    ],
    released: '2026-09-26',
    updated: '2026-09-26',
  ),
  'game-counter': ToolDetails(
    tags: [
      ToolText('Board games', '桌游'),
      ToolText('Score', '计分'),
      ToolText('Multiplayer', '多人'),
      ToolText('Party', '聚会'),
    ],
    scope: ToolText(
      'Keep score for board games, card games and party games with several '
          'players.',
      '为桌游、卡牌和聚会游戏记录多位玩家的分数。',
    ),
    limitations: [
      ToolText('Only one scene is active at a time.', '同一时间只能使用一个场景。'),
      ToolText(
        'History is stored per scene and can be cleared from the history '
            'screen.',
        '历史记录按场景保存，可在历史界面清除。',
      ),
      ToolText('Scores live on this device only.', '分数只保存在本机。'),
    ],
    released: '2026-09-27',
    updated: '2026-09-27',
  ),
  'basexx': ToolDetails(
    tags: [
      ToolText('Developer', '开发者'),
      ToolText('Encoding', '编码'),
      ToolText('Text', '文本'),
    ],
    scope: ToolText(
      'Convert text between Base16, Base32, Base58 and Base64, for example '
          'tokens, IDs and debugging payloads.',
      '在 Base16、Base32、Base58 与 Base64 之间转换文本，适合令牌、ID 和调试。',
    ),
    limitations: [
      ToolText(
        'Works on text only; there is no file or binary input.',
        '仅支持文本，不能直接处理文件或二进制数据。',
      ),
      ToolText(
        'Invalid input shows an error instead of guessing a repair.',
        '输入无效时会报错，不会尝试猜测修复。',
      ),
      ToolText('Large inputs are processed in memory.', '较大的输入全部在内存中处理。'),
    ],
    released: '2026-09-26',
    updated: '2026-09-26',
  ),
  '2048': ToolDetails(
    tags: [
      ToolText('Game', '游戏'),
      ToolText('Puzzle', '益智'),
      ToolText('Offline', '离线'),
    ],
    scope: ToolText(
      'Take a short break with the classic sliding tile puzzle.',
      '用经典滑动方块拼图休息片刻。',
    ),
    limitations: [
      ToolText(
        'Auto play does not guarantee reaching 2048.',
        '自动游玩不保证能合成 2048。',
      ),
      ToolText(
        'Large boards need more screen space and are cramped on small phones.',
        '大棋盘需要更多屏幕空间，小屏手机上会比较拥挤。',
      ),
      ToolText('Scores are not uploaded anywhere.', '分数不会上传到任何地方。'),
    ],
    released: '2026-09-26',
    updated: '2026-09-26',
  ),
  'tic-tac-toe': ToolDetails(
    tags: [
      ToolText('Game', '游戏'),
      ToolText('Board', '棋盘'),
      ToolText('Bot', '机器人'),
    ],
    scope: ToolText(
      'Play a quick match against the bot or with a friend on one device.',
      '与电脑或同一台设备上的朋友来一局快速对战。',
    ),
    limitations: [
      ToolText(
        'The bot does not learn and plays the same way on the same difficulty.',
        '机器人不会学习，同一难度下走法固定。',
      ),
      ToolText('Two-player mode shares one screen.', '双人模式共用一块屏幕。'),
      ToolText('Custom marks are text only.', '自定义符号只支持文本。'),
    ],
    released: '2026-09-26',
    updated: '2026-09-26',
  ),
  'flashlight': ToolDetails(
    tags: [
      ToolText('Hardware', '硬件'),
      ToolText('Light', '照明'),
      ToolText('Morse', '摩尔斯'),
      ToolText('SOS', '求救'),
    ],
    scope: ToolText(
      'Light up dark spaces, send SOS signals or practise Morse code.',
      '在黑暗环境中照明、发送 SOS 信号或练习摩尔斯电码。',
    ),
    limitations: [
      ToolText(
        'Needs a camera flash; desktop platforms only offer Morse code.',
        '需要相机闪光灯；桌面平台只保留摩尔斯电码。',
      ),
      ToolText(
        'Brightness control depends on hardware support.',
        '亮度调节取决于硬件是否支持。',
      ),
      ToolText(
        'Sustained use may heat the LED and drain the battery.',
        '长时间使用会使 LED 发热并消耗电量。',
      ),
    ],
    platforms: _desktopPartialPlatforms,
    released: '2026-09-26',
    updated: '2026-09-26',
  ),
  'vibrator': ToolDetails(
    tags: [
      ToolText('Hardware', '硬件'),
      ToolText('Haptics', '触感'),
      ToolText('Patterns', '模式'),
    ],
    scope: ToolText(
      'Test vibration, build custom patterns or use tactile timing cues.',
      '测试震动、编排自定义模式，或作为触感提示。',
    ),
    limitations: [
      ToolText(
        'Needs a vibration motor; desktop platforms have no vibration '
            'hardware.',
        '需要震动马达；桌面平台没有震动硬件。',
      ),
      ToolText(
        'Custom patterns use the comma-separated format shown in the app.',
        '自定义模式需使用应用中展示的逗号分隔格式。',
      ),
      ToolText('Vibration strength is controlled by the system.', '震动强度由系统控制。'),
    ],
    platforms: _mobileOnlyPlatforms,
    released: '2026-09-27',
    updated: '2026-09-27',
  ),
  'tone-generator': ToolDetails(
    tags: [
      ToolText('Audio', '音频'),
      ToolText('Frequency', '频率'),
      ToolText('Health', '健康'),
      ToolText('Testing', '测试'),
    ],
    scope: ToolText(
      'Test speakers and headphones, mask noise, or try the 100 Hz '
          'motion-sickness note.',
      '测试扬声器与耳机、掩蔽噪声，或尝试 100 Hz 缓解晕车音。',
    ),
    limitations: [
      ToolText(
        'High volume can distort small speakers; start low.',
        '高音量会让小扬声器失真，请从低音量开始。',
      ),
      ToolText(
        'Playback keeps running in the background until you stop it.',
        '播放会在后台持续，直到手动停止。',
      ),
      ToolText(
        'The 100 Hz note is a comfort aid, not medical advice.',
        '100 Hz 说明仅为舒适性参考，不构成医疗建议。',
      ),
    ],
    released: '2026-10-24',
    updated: '2026-10-25',
  ),
  'speaker-cleaner': ToolDetails(
    tags: [
      ToolText('Audio', '音频'),
      ToolText('Maintenance', '维护'),
      ToolText('Hardware', '硬件'),
    ],
    scope: ToolText(
      'Pulse low tones and vibration to shake water or dust out of a phone '
          'speaker.',
      '用低频脉冲与震动把手机扬声器里的水或灰尘震出。',
    ),
    limitations: [
      ToolText(
        'Water ejection is not guaranteed; repeat only a few times.',
        '不保证能完全排水，请只重复少量次数。',
      ),
      ToolText(
        'Keep away from charging ports and do not use at full volume.',
        '远离充电口，不要使用最大音量。',
      ),
      ToolText(
        'Desktop platforms have no speaker water protection and no '
            'vibration.',
        '桌面平台没有扬声器防水需求，也没有震动。',
      ),
    ],
    platforms: _desktopPartialPlatforms,
    released: '2026-10-26',
    updated: '2026-10-26',
  ),
  'clock': ToolDetails(
    tags: [
      ToolText('Time', '时间'),
      ToolText('Display', '显示'),
      ToolText('Wake lock', '常亮'),
    ],
    scope: ToolText(
      'Turn the device into a bedside or desk clock with five faces and a '
          'wake lock.',
      '把设备变成床头或桌面时钟，提供五种表盘与屏幕常亮。',
    ),
    limitations: [
      ToolText(
        'The wake lock keeps the screen on and increases battery use.',
        '屏幕常亮会明显增加耗电。',
      ),
      ToolText(
        'Fullscreen mode hides the system bars and the app bar.',
        '全屏模式会隐藏系统栏与应用栏。',
      ),
      ToolText(
        'Some faces animate continuously and may drop frames on older '
            'devices.',
        '部分表盘持续动画，旧设备上可能掉帧。',
      ),
    ],
    released: '2026-10-26',
    updated: '2026-10-26',
  ),
  'world-clock': ToolDetails(
    tags: [
      ToolText('Time', '时间'),
      ToolText('Timezones', '时区'),
      ToolText('Travel', '出行'),
      ToolText('Display', '显示'),
    ],
    scope: ToolText(
      'Check several time zones at a glance on a desk, wall or travel '
          'display.',
      '在桌面、墙面或旅途中一眼查看多个时区。',
    ),
    limitations: [
      ToolText(
        'Time zones come from a bundled IANA database; very recent political '
            'changes may lag.',
        '时区数据来自内置的 IANA 数据库，最新的政治变更可能滞后。',
      ),
      ToolText(
        'The city list is curated, not every city is included.',
        '城市列表经过挑选，并未收录所有城市。',
      ),
      ToolText(
        'The flip board is designed for dark backgrounds and can be bright at '
            'night.',
        '翻页牌为深色背景设计，夜间可能偏亮。',
      ),
    ],
    released: '2026-10-26',
    updated: '2026-10-26',
  ),
};

ToolDetails? toolDetailsFor(String id) => toolDetailsById[id];

String toolCreditDescription(
  BuildContext context,
  ToolInfo tool,
  ToolCredit credit,
) {
  if (credit.englishDescription.isNotEmpty) {
    return tr(context, credit.englishDescription, credit.chineseDescription);
  }
  return tr(
    context,
    'The ${tool.englishTitle} tool is inspired by the open-source '
        '${credit.project} by ${credit.author}.',
    '${tool.chineseTitle}的界面与思路灵感来自 ${credit.author} 的开源项目 '
        '${credit.project}。',
  );
}

Future<void> openToolUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(url)));
    }
  }
}

class _ToolLink extends StatelessWidget {
  const _ToolLink({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => openToolUrl(context, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_new, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                url,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  decoration: TextDecoration.underline,
                  decorationColor: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LicenseBadge extends StatelessWidget {
  const _LicenseBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_outlined,
            size: 16,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String toolPlatformName(ToolPlatform platform) => switch (platform) {
  ToolPlatform.android => 'Android',
  ToolPlatform.ios => 'iOS',
  ToolPlatform.macos => 'macOS',
  ToolPlatform.windows => 'Windows',
  ToolPlatform.linux => 'Linux',
};

IconData _toolPlatformIcon(ToolPlatform platform) => switch (platform) {
  ToolPlatform.android => Icons.phone_android,
  ToolPlatform.ios => Icons.phone_iphone,
  ToolPlatform.macos => Icons.laptop_mac,
  ToolPlatform.windows => Icons.desktop_windows,
  ToolPlatform.linux => Icons.computer,
};

Future<void> openToolDetails(BuildContext context, String toolId) {
  final tool = toolInfoById(toolId);
  if (tool == null) return Future<void>.value();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ToolDetailsScreen(tool: tool)),
  );
}

Widget toolInfoAction(BuildContext context, String toolId) => IconButton(
  key: ValueKey('tool-info-$toolId'),
  tooltip: tr(context, 'Tool details', '工具详细信息'),
  onPressed: () => unawaited(openToolDetails(context, toolId)),
  icon: const Icon(Icons.info_outline),
);

class ToolDetailsScreen extends StatelessWidget {
  const ToolDetailsScreen({super.key, required this.tool});

  final ToolInfo tool;

  @override
  Widget build(BuildContext context) {
    final details = toolDetailsById[tool.id]!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'Tool details', '工具详细信息'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            key: ValueKey('tool-details-${tool.id}'),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
            children: [
              _ToolDetailHeader(tool: tool, details: details),
              const SizedBox(height: 16),
              _ToolDetailCard(
                icon: Icons.explore_outlined,
                title: tr(context, 'Best for', '适用范围'),
                child: Text(
                  details.scope.resolve(context),
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ),
              const SizedBox(height: 12),
              _ToolDetailCard(
                icon: Icons.devices_outlined,
                title: tr(context, 'Device support', '适配情况'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final status in details.platforms)
                      _ToolDetailPlatformRow(status: status),
                    if (tool.englishNote.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        tr(context, tool.englishNote, tool.chineseNote),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ToolDetailCard(
                icon: Icons.sell_outlined,
                title: tr(context, 'Version and dates', '版本与日期'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ToolDetailMetaRow(
                      label: tr(context, 'Version', '版本'),
                      value: details.version,
                    ),
                    _ToolDetailMetaRow(
                      label: tr(context, 'Released', '发布日期'),
                      value: details.released,
                    ),
                    _ToolDetailMetaRow(
                      label: tr(context, 'Last updated', '最后更新'),
                      value: details.updated,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ToolDetailCard(
                icon: Icons.bug_report_outlined,
                title: tr(context, 'Known limitations', '已知缺陷'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final limitation in details.limitations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Icon(
                                Icons.circle,
                                size: 6,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                limitation.resolve(context),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _ToolDetailCard(
                icon: Icons.handshake_outlined,
                title: tr(context, 'Acknowledgements', '致谢'),
                child: _ToolCreditList(tool: tool),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolDetailHeader extends StatelessWidget {
  const _ToolDetailHeader({required this.tool, required this.details});

  final ToolInfo tool;
  final ToolDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Icon(tool.icon, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, tool.englishTitle, tool.chineseTitle),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr(context, tool.englishSubtitle, tool.chineseSubtitle),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in details.tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tag.resolve(context),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolDetailCard extends StatelessWidget {
  const _ToolDetailCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ToolDetailMetaRow extends StatelessWidget {
  const _ToolDetailMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolDetailPlatformRow extends StatelessWidget {
  const _ToolDetailPlatformRow({required this.status});

  final ToolPlatformStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color, label) = switch (status.support) {
      ToolPlatformSupport.full => (
        Icons.check_circle_outline,
        scheme.primary,
        tr(context, 'Supported', '支持'),
      ),
      ToolPlatformSupport.partial => (
        Icons.remove_circle_outline,
        Colors.amber,
        tr(context, 'Partial', '部分支持'),
      ),
      ToolPlatformSupport.none => (
        Icons.block_outlined,
        scheme.onSurfaceVariant,
        tr(context, 'Not available', '不支持'),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            _toolPlatformIcon(status.platform),
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              toolPlatformName(status.platform),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCreditList extends StatelessWidget {
  const _ToolCreditList({required this.tool});

  final ToolInfo tool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!tool.hasAcknowledgements) {
      return Text(
        tr(context, 'No acknowledgements for this tool.', '此工具没有需要标记的致谢信息。'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tool.credits.length; i++) ...[
          if (i > 0) const Divider(height: 24),
          Text(toolCreditDescription(context, tool, tool.credits[i])),
          const SizedBox(height: 12),
          _LicenseBadge(
            text: tr(
              context,
              'License: ${tool.credits[i].license}',
              '许可证：${tool.credits[i].license}',
            ),
          ),
          const SizedBox(height: 8),
          _ToolLink(url: tool.credits[i].url),
        ],
      ],
    );
  }
}

Future<void> openVault(BuildContext context) async {
  final store = VaultStore();
  await store.initialize();
  if (!context.mounted) return;
  await Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => UnlockScreen(store: store)));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Map<HomeView, TextEditingController> _searchControllers = {
    for (final view in HomeView.core) view: TextEditingController(),
  };
  late final Map<HomeView, FocusNode> _searchFocusNodes;

  @override
  void initState() {
    super.initState();
    _searchFocusNodes = {
      for (final view in HomeView.core)
        view: FocusNode()..addListener(_onSearchFocusChanged),
    };
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in _searchControllers.values) {
      controller.dispose();
    }
    for (final node in _searchFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Widget? _screenFor(String id) => switch (id) {
    'password-generator' => const GeneratorScreen(),
    'counter' => const CounterScreen(),
    'game-counter' => const GameCounterScreen(),
    'basexx' => const BaseCodecScreen(),
    '2048' => const Game2048Screen(),
    'tic-tac-toe' => const TicTacToeScreen(),
    'flashlight' => const FlashlightScreen(),
    'vibrator' => const VibratorScreen(),
    'tone-generator' => const ToneGeneratorScreen(),
    'speaker-cleaner' => const SpeakerCleanerScreen(),
    'clock' => const ClockScreen(),
    'world-clock' => const WorldClockScreen(),
    _ => null,
  };

  void _openSettings(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  Widget? _settingsFallback(BuildContext context, AppSettings settings) {
    if (settings.isHomeViewVisible(HomeView.settings)) return null;
    return IconButton(
      key: const ValueKey('home-settings-fallback'),
      tooltip: tr(context, 'Settings', '设置'),
      onPressed: () => _openSettings(context),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.tune),
    );
  }

  void _openTool(BuildContext context, AppSettings settings, ToolInfo tool) {
    final screen = _screenFor(tool.id);
    if (screen == null) return;
    unawaited(settings.markToolOpened(tool.id));
    _open(context, screen);
  }

  List<ToolInfo> _filterTools(String query, List<ToolInfo> tools) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return tools;
    return [
      for (final tool in tools)
        if (_toolMatches(tool, needle)) tool,
    ];
  }

  bool _toolMatches(ToolInfo tool, String needle) {
    if (tool.englishTitle.toLowerCase().contains(needle) ||
        tool.chineseTitle.contains(needle) ||
        tool.englishSubtitle.toLowerCase().contains(needle) ||
        tool.chineseSubtitle.contains(needle) ||
        tool.id.toLowerCase().contains(needle)) {
      return true;
    }
    final details = toolDetailsById[tool.id];
    if (details == null) return false;
    return details.tags.any(
      (tag) =>
          tag.english.toLowerCase().contains(needle) ||
          tag.chinese.contains(needle),
    );
  }

  String _toolCount(
    BuildContext context,
    int count, {
    required bool searching,
  }) {
    if (searching) {
      return tr(
        context,
        count == 1 ? '1 result' : '$count results',
        '$count 个结果',
      );
    }
    return tr(context, count == 1 ? '1 tool' : '$count tools', '$count 个工具');
  }

  Widget _searchBar(BuildContext context, HomeView view) {
    final controller = _searchControllers[view]!;
    return TextField(
      key: ValueKey('home-search-${view.name}'),
      controller: controller,
      focusNode: _searchFocusNodes[view],
      textInputAction: TextInputAction.search,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _searchFocusNodes[view]?.unfocus(),
      onTapOutside: (_) => _searchFocusNodes[view]?.unfocus(),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search, size: 20),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        hintText: tr(context, 'Search tools', '搜索工具'),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                key: ValueKey('home-search-clear-${view.name}'),
                tooltip: tr(context, 'Clear search', '清除搜索'),
                onPressed: () {
                  controller.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close, size: 18),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _toolTile(BuildContext context, AppSettings settings, ToolInfo tool) {
    final favorite = settings.favoriteToolIds.contains(tool.id);
    return _ToolTile(
      key: ValueKey('tool-tile-${tool.id}'),
      toolId: tool.id,
      icon: tool.icon,
      title: tr(context, tool.englishTitle, tool.chineseTitle),
      subtitle: tr(context, tool.englishSubtitle, tool.chineseSubtitle),
      favorite: favorite,
      onToggleFavorite: () => unawaited(settings.toggleFavorite(tool.id)),
      onTap: () => _openTool(context, settings, tool),
    );
  }

  Widget _toolGrid(
    BuildContext context,
    AppSettings settings,
    List<ToolInfo> tools, {
    required bool wide,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = wide ? (constraints.maxWidth >= 1040 ? 3 : 2) : 1;
        const gap = 12.0;
        final rows = <Widget>[];
        for (var start = 0; start < tools.length; start += columns) {
          final end = start + columns > tools.length
              ? tools.length
              : start + columns;
          final rowTools = tools.sublist(start, end);
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < columns; index++) ...[
                    if (index < rowTools.length)
                      Expanded(
                        child: _toolTile(context, settings, rowTools[index]),
                      )
                    else
                      const Spacer(),
                    if (index < columns - 1) const SizedBox(width: gap),
                  ],
                ],
              ),
            ),
          );
          if (end < tools.length) rows.add(const SizedBox(height: gap));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  Widget _searchEmpty(
    BuildContext context,
    HomeView view,
    TextEditingController controller,
  ) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: _HomeEmptyState(
        key: ValueKey('home-search-empty-${view.name}'),
        icon: Icons.search_off,
        title: tr(context, 'No matching tools', '没有匹配的工具'),
        subtitle: tr(
          context,
          'Try a different keyword or clear the search.',
          '试试其他关键词或清除搜索。',
        ),
        actionLabel: tr(context, 'Clear search', '清除搜索'),
        actionIcon: Icons.close,
        onAction: () {
          controller.clear();
          setState(() {});
        },
      ),
    ),
  );

  Widget _recentEmpty(BuildContext context, AppSettings settings) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: _HomeEmptyState(
        key: const ValueKey('home-recent-empty'),
        icon: Icons.history,
        title: tr(context, 'No recent tools', '还没有最近记录'),
        subtitle: tr(
          context,
          'Open a tool and it will appear here.',
          '打开一个工具后会显示在这里。',
        ),
        actionLabel: settings.isHomeViewVisible(HomeView.all)
            ? tr(context, 'Browse all tools', '浏览全部工具')
            : null,
        actionIcon: Icons.grid_view_outlined,
        onAction: settings.isHomeViewVisible(HomeView.all)
            ? () => unawaited(settings.setHomeTab(HomeView.all))
            : null,
      ),
    ),
  );

  Widget _favoritesEmpty(BuildContext context, AppSettings settings) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: _HomeEmptyState(
        key: const ValueKey('home-favorites-empty'),
        icon: Icons.star_border,
        title: tr(context, 'No favorites yet', '还没有收藏'),
        subtitle: tr(
          context,
          'Tap the star on a tool in All to save it here.',
          '在「全部」中点击工具旁的星标即可收藏。',
        ),
        actionLabel: settings.isHomeViewVisible(HomeView.all)
            ? tr(context, 'Browse all tools', '浏览全部工具')
            : null,
        actionIcon: Icons.grid_view_outlined,
        onAction: settings.isHomeViewVisible(HomeView.all)
            ? () => unawaited(settings.setHomeTab(HomeView.all))
            : null,
      ),
    ),
  );

  Widget _allView(
    BuildContext context,
    AppSettings settings, {
    required bool wide,
  }) {
    final controller = _searchControllers[HomeView.all]!;
    final searching = controller.text.trim().isNotEmpty;
    final expanded = !wide && _searchFocusNodes[HomeView.all]!.hasFocus;
    final tools = _filterTools(controller.text, toolInfos);
    return ListView(
      key: const PageStorageKey('home-all'),
      padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 20, wide ? 32 : 20, 36),
      children: [
        _HomeSectionHeader(
          title: tr(context, 'Pockito', '妙物袋'),
          onTitleLongPress: () => openVault(context),
          subtitle: _toolCount(context, tools.length, searching: searching),
          action: _searchBar(context, HomeView.all),
          trailing: _settingsFallback(context, settings),
          expanded: expanded,
          compactActionWidth: wide ? 320 : 172,
        ),
        const SizedBox(height: 16),
        if (tools.isEmpty)
          _searchEmpty(context, HomeView.all, controller)
        else
          _toolGrid(context, settings, tools, wide: wide),
      ],
    );
  }

  Widget _recentView(
    BuildContext context,
    AppSettings settings, {
    required bool wide,
  }) {
    final controller = _searchControllers[HomeView.recent]!;
    final baseTools = [
      for (final id in settings.recentToolIds) ?toolInfoById(id),
    ];
    final searching = controller.text.trim().isNotEmpty;
    final expanded = !wide && _searchFocusNodes[HomeView.recent]!.hasFocus;
    final tools = _filterTools(controller.text, baseTools);
    return ListView(
      key: const PageStorageKey('home-recent'),
      padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 20, wide ? 32 : 20, 36),
      children: [
        _HomeSectionHeader(
          title: tr(context, 'Recent', '最近'),
          onTitleLongPress: () => openVault(context),
          subtitle: baseTools.isEmpty
              ? tr(context, 'No recent tools yet', '还没有最近记录')
              : _toolCount(context, tools.length, searching: searching),
          action: baseTools.isEmpty
              ? null
              : _searchBar(context, HomeView.recent),
          trailing: _settingsFallback(context, settings),
          expanded: expanded,
          compactActionWidth: wide ? 320 : 172,
        ),
        const SizedBox(height: 16),
        if (baseTools.isEmpty)
          _recentEmpty(context, settings)
        else if (tools.isEmpty)
          _searchEmpty(context, HomeView.recent, controller)
        else
          _toolGrid(context, settings, tools, wide: wide),
      ],
    );
  }

  Widget _favoritesView(
    BuildContext context,
    AppSettings settings, {
    required bool wide,
  }) {
    final controller = _searchControllers[HomeView.favorites]!;
    final baseTools = [
      for (final tool in toolInfos)
        if (settings.favoriteToolIds.contains(tool.id)) tool,
    ];
    final searching = controller.text.trim().isNotEmpty;
    final expanded = !wide && _searchFocusNodes[HomeView.favorites]!.hasFocus;
    final tools = _filterTools(controller.text, baseTools);
    return ListView(
      key: const PageStorageKey('home-favorites'),
      padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 20, wide ? 32 : 20, 36),
      children: [
        _HomeSectionHeader(
          title: tr(context, 'Favorites', '收藏'),
          onTitleLongPress: () => openVault(context),
          subtitle: baseTools.isEmpty
              ? tr(context, 'No favorites yet', '还没有收藏')
              : _toolCount(context, tools.length, searching: searching),
          action: baseTools.isEmpty
              ? null
              : _searchBar(context, HomeView.favorites),
          trailing: _settingsFallback(context, settings),
          expanded: expanded,
          compactActionWidth: wide ? 320 : 172,
        ),
        const SizedBox(height: 16),
        if (baseTools.isEmpty)
          _favoritesEmpty(context, settings)
        else if (tools.isEmpty)
          _searchEmpty(context, HomeView.favorites, controller)
        else
          _toolGrid(context, settings, tools, wide: wide),
      ],
    );
  }

  Widget _viewFor(
    BuildContext context,
    AppSettings settings,
    HomeView view, {
    required bool wide,
  }) => switch (view) {
    HomeView.recent => _recentView(context, settings, wide: wide),
    HomeView.favorites => _favoritesView(context, settings, wide: wide),
    HomeView.all => _allView(context, settings, wide: wide),
    HomeView.settings => SettingsView(
      onTitleLongPress: () => openVault(context),
    ),
  };

  Widget _homeRail(
    BuildContext context,
    AppSettings settings,
    List<HomeView> visibleViews,
    HomeView currentView,
  ) => NavigationRail(
    selectedIndex: visibleViews.indexOf(currentView),
    onDestinationSelected: (index) {
      unawaited(settings.setHomeTab(visibleViews[index]));
    },
    labelType: NavigationRailLabelType.all,
    groupAlignment: -1,
    backgroundColor: Theme.of(context).colorScheme.surface,
    destinations: [
      for (final view in visibleViews)
        NavigationRailDestination(
          icon: Icon(view.icon),
          selectedIcon: Icon(view.selectedIcon),
          label: KeyedSubtree(
            key: ValueKey('home-nav-${view.name}'),
            child: Text(tr(context, view.englishName, view.chineseName)),
          ),
        ),
    ],
  );

  Widget _bottomNav(
    BuildContext context,
    AppSettings settings,
    List<HomeView> visibleViews,
    HomeView currentView,
  ) => NavigationBar(
    selectedIndex: visibleViews.indexOf(currentView),
    onDestinationSelected: (index) {
      unawaited(settings.setHomeTab(visibleViews[index]));
    },
    destinations: [
      for (final view in visibleViews)
        NavigationDestination(
          key: ValueKey('home-nav-${view.name}'),
          icon: Icon(view.icon),
          selectedIcon: Icon(view.selectedIcon),
          label: tr(context, view.englishName, view.chineseName),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    final visibleViews = settings.visibleHomeViews;
    final currentView = visibleViews.contains(settings.homeTab)
        ? settings.homeTab
        : visibleViews.first;
    final showNavigation = visibleViews.length > 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Scaffold(
          body: SafeArea(
            top: true,
            bottom: false,
            child: wide
                ? Row(
                    children: [
                      if (showNavigation) ...[
                        _homeRail(context, settings, visibleViews, currentView),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: currentView == HomeView.settings
                                  ? 720
                                  : 1120,
                            ),
                            child: _viewFor(
                              context,
                              settings,
                              currentView,
                              wide: wide,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: _viewFor(
                        context,
                        settings,
                        currentView,
                        wide: false,
                      ),
                    ),
                  ),
          ),
          bottomNavigationBar: !wide && showNavigation
              ? _bottomNav(context, settings, visibleViews, currentView)
              : null,
        );
      },
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    super.key,
    required this.toolId,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.favorite,
    required this.onToggleFavorite,
    required this.onTap,
  });

  final String toolId;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool favorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('tool-card-$toolId'),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: Icon(icon),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('tool-favorite-$toolId'),
                    tooltip: favorite
                        ? tr(context, 'Remove from favorites', '取消收藏')
                        : tr(context, 'Add to favorites', '收藏'),
                    onPressed: onToggleFavorite,
                    icon: Icon(
                      favorite ? Icons.star : Icons.star_border,
                      color: favorite ? Colors.amber : null,
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    required this.title,
    required this.subtitle,
    this.action,
    this.trailing,
    this.expanded = false,
    this.compactActionWidth = 0,
    this.onTitleLongPress,
  });

  final String title;
  final String subtitle;
  final Widget? action;
  final Widget? trailing;
  final bool expanded;
  final double compactActionWidth;
  final VoidCallback? onTitleLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleWidget = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onTitleLongPress == null)
          titleWidget
        else
          GestureDetector(onLongPress: onTitleLongPress, child: titleWidget),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    if (action == null) {
      if (trailing == null) return titleColumn;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: titleColumn),
          const SizedBox(width: 8),
          trailing!,
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final trailingSpace = trailing == null ? 0.0 : 56.0;
        final compactWidth = compactActionWidth
            .clamp(0.0, constraints.maxWidth)
            .toDouble();
        final maxExpandedWidth =
            (constraints.maxWidth - 110 - 12 - trailingSpace)
                .clamp(compactWidth, constraints.maxWidth)
                .toDouble();
        final targetWidth = expanded
            ? min(compactWidth + 48, maxExpandedWidth)
            : compactWidth;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: titleColumn),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: targetWidth,
              child: action!,
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        );
      },
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.actionIcon = Icons.grid_view_outlined,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
        child: Column(
          children: [
            Icon(icon, size: 42, color: theme.colorScheme.primary),
            const SizedBox(height: 14),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onAction != null && actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onAction,
                icon: Icon(actionIcon),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppearanceControls extends StatelessWidget {
  const _AppearanceControls({this.showLabels = false});

  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showLabels) ...[
          Text(tr(context, 'Theme', '主题'), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
        ],
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
              value: ThemeMode.system,
              icon: const Icon(Icons.brightness_auto_outlined),
              label: Text(tr(context, 'System', '系统')),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: const Icon(Icons.light_mode_outlined),
              label: Text(tr(context, 'Light', '浅色')),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: const Icon(Icons.dark_mode_outlined),
              label: Text(tr(context, 'Dark', '深色')),
            ),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (selection) {
            unawaited(settings.setTheme(selection.first));
          },
        ),
        SizedBox(height: showLabels ? 16 : 12),
        if (showLabels) ...[
          Text(
            tr(context, 'Language', '语言'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
        ],
        SegmentedButton<LocaleMode>(
          segments: [
            ButtonSegment(
              value: LocaleMode.system,
              icon: const Icon(Icons.language_outlined),
              label: Text(tr(context, 'System', '系统')),
            ),
            ButtonSegment(
              value: LocaleMode.english,
              icon: const Icon(Icons.translate),
              label: const Text('English'),
            ),
            ButtonSegment(
              value: LocaleMode.chinese,
              icon: const Icon(Icons.translate),
              label: const Text('中文'),
            ),
          ],
          selected: {settings.localeMode},
          onSelectionChanged: (selection) {
            unawaited(settings.setLocaleMode(selection.first));
          },
        ),
        const SizedBox(height: 20),
        const _ThemeColorControls(),
      ],
    );
  }
}

class _ThemeColorControls extends StatelessWidget {
  const _ThemeColorControls();

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    final theme = Theme.of(context);
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final dynamicAvailable =
            Platform.isAndroid && lightDynamic != null && darkDynamic != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(context, 'Theme color', '主题色'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            if (dynamicAvailable)
              SwitchListTile(
                key: const ValueKey('settings-material-you'),
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.auto_awesome_outlined),
                title: Text(tr(context, 'Material You', 'Material You')),
                subtitle: Text(
                  tr(
                    context,
                    'Use colors sampled from the Android wallpaper.',
                    '使用 Android 系统壁纸取色。',
                  ),
                ),
                value: settings.useDynamicColor,
                onChanged: (value) {
                  unawaited(settings.setUseDynamicColor(value));
                },
              ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final preset in themeAccentPresets)
                  _ThemeColorSwatch(
                    preset: preset,
                    dynamicActive: dynamicAvailable && settings.useDynamicColor,
                  ),
              ],
            ),
            if (dynamicAvailable && settings.useDynamicColor) ...[
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  'Choosing a color below leaves Material You.',
                  '选择下方颜色会退出 Material You。',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ThemeColorSwatch extends StatelessWidget {
  const _ThemeColorSwatch({required this.preset, required this.dynamicActive});

  final ThemeAccentPreset preset;
  final bool dynamicActive;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = Color(preset.color);
    final selected = !dynamicActive && settings.accentColor == preset.color;
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final label = tr(context, preset.englishName, preset.chineseName);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          key: ValueKey('settings-accent-${preset.id}'),
          customBorder: const CircleBorder(),
          onTap: () => unawaited(settings.setAccentColor(preset.color)),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: selected
                ? Icon(Icons.check, size: 18, color: foreground)
                : null,
          ),
        ),
      ),
    );
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    this.showHeader = true,
    this.onTitleLongPress,
  });

  final bool showHeader;
  final VoidCallback? onTitleLongPress;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    final theme = Theme.of(context);
    final headerTitle = Text(
      tr(context, 'Settings', '设置'),
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    return ListView(
      key: const PageStorageKey('home-settings'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      children: [
        if (showHeader) ...[
          if (onTitleLongPress == null)
            headerTitle
          else
            GestureDetector(onLongPress: onTitleLongPress, child: headerTitle),
          const SizedBox(height: 4),
          Text(
            tr(context, 'Appearance, language and home tabs.', '外观、语言与首页界面。'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
        ],
        Text(
          tr(context, 'Appearance', '外观'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        const _AppearanceControls(showLabels: true),
        const SizedBox(height: 22),
        const Divider(height: 1),
        const SizedBox(height: 18),
        Text(
          tr(context, 'Home tabs', '首页界面'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          tr(
            context,
            'Choose which views appear in the home navigation.',
            '选择首页导航中显示的界面。',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          key: const ValueKey('home-remember-tab'),
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.restore),
          title: Text(tr(context, 'Remember last view', '记住上次界面')),
          subtitle: Text(
            tr(
              context,
              'Open the app on the last view you used.',
              '下次打开时回到上次使用的界面。',
            ),
          ),
          value: settings.rememberHomeTab,
          onChanged: (value) {
            unawaited(settings.setRememberHomeTab(value));
          },
        ),
        for (final view in HomeView.values) _HomeViewSwitch(view: view),
        const SizedBox(height: 6),
        Text(
          tr(
            context,
            'At least one of Recent, Favorites and All must stay visible.',
            '最近、收藏、全部至少保留一个。',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        const Divider(height: 1),
        const SizedBox(height: 18),
        Text(
          tr(context, 'Recent and favorites', '最近与收藏'),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              key: const ValueKey('settings-clear-recent'),
              onPressed: settings.recentToolIds.isEmpty
                  ? null
                  : () => unawaited(settings.clearRecent()),
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(tr(context, 'Clear recent', '清空最近')),
            ),
            TextButton.icon(
              key: const ValueKey('settings-clear-favorites'),
              onPressed: settings.favoriteToolIds.isEmpty
                  ? null
                  : () => unawaited(settings.clearFavorites()),
              icon: const Icon(Icons.star_border),
              label: Text(tr(context, 'Clear favorites', '清空收藏')),
            ),
          ],
        ),
      ],
    );
  }
}

class _HomeViewSwitch extends StatelessWidget {
  const _HomeViewSwitch({required this.view});

  final HomeView view;

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.of(context);
    final visible = settings.isHomeViewVisible(view);
    final canToggle = !visible || settings.canHideHomeView(view);
    return SwitchListTile(
      key: ValueKey('home-show-${view.name}'),
      contentPadding: EdgeInsets.zero,
      secondary: Icon(view.icon),
      title: Text(tr(context, view.englishName, view.chineseName)),
      subtitle: Text(
        canToggle
            ? tr(context, view.englishSubtitle, view.chineseSubtitle)
            : tr(
                context,
                'At least one tool view must stay visible.',
                '至少保留一个工具界面。',
              ),
      ),
      value: visible,
      onChanged: canToggle
          ? (value) => unawaited(settings.setHomeViewVisible(view, value))
          : null,
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr(context, 'Settings', '设置'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: const SettingsView(showHeader: false),
      ),
    ),
  );
}

class CounterRecord {
  CounterRecord({required this.time, required this.delta, required this.value});

  final DateTime time;
  final int delta;
  final int value;

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'delta': delta,
    'value': value,
  };

  factory CounterRecord.fromJson(Map<String, dynamic> json) => CounterRecord(
    time: DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
    delta: (json['delta'] as num?)?.toInt() ?? 0,
    value: (json['value'] as num?)?.toInt() ?? 0,
  );
}

String formatTimestamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

class CounterItem {
  CounterItem({
    required this.id,
    required this.name,
    required this.count,
    required this.updatedAt,
    List<CounterRecord>? records,
  }) : records = records ?? [];

  final String id;
  String name;
  int count;
  DateTime updatedAt;
  final List<CounterRecord> records;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'count': count,
    'updatedAt': updatedAt.toIso8601String(),
    'records': records.map((record) => record.toJson()).toList(),
  };

  factory CounterItem.fromJson(Map<String, dynamic> json) => CounterItem(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    count: (json['count'] as num?)?.toInt() ?? 0,
    updatedAt:
        DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
    records: (json['records'] as List?)
        ?.whereType<Map>()
        .map(
          (entry) => CounterRecord.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(),
  );
}

class CounterStore {
  CounterStore([this._directory]);
  static const _fileName = 'tool_counters.json';
  final Directory? _directory;
  File? _file;

  Future<File> _resolveFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final directory = _directory ?? await getApplicationSupportDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$_fileName');
    _file = file;
    return file;
  }

  Future<List<CounterItem>> load() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return [];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (entry) => CounterItem.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<CounterItem> items) async {
    try {
      final file = await _resolveFile();
      await file.writeAsString(
        jsonEncode(items.map((item) => item.toJson()).toList()),
        flush: true,
      );
    } catch (_) {}
  }
}

class GameCounterType {
  GameCounterType({
    required this.id,
    required this.name,
    this.quickDirection = 1,
    this.defaultValue = 0,
  });

  final String id;
  String name;
  int quickDirection;
  int defaultValue;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'quickDirection': quickDirection,
    'defaultValue': defaultValue,
  };

  factory GameCounterType.fromJson(Map<String, dynamic> json) =>
      GameCounterType(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        quickDirection: ((json['quickDirection'] as num?)?.toInt() ?? 1) < 0
            ? -1
            : 1,
        defaultValue: (json['defaultValue'] as num?)?.toInt() ?? 0,
      );
}

class GameUser {
  GameUser({
    required this.id,
    this.name = '',
    this.activeIndex = 0,
    this.rotation = 0,
  });

  final String id;
  String name;
  int activeIndex;
  int rotation;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'activeIndex': activeIndex,
    'rotation': rotation,
  };

  factory GameUser.fromJson(Map<String, dynamic> json) => GameUser(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    activeIndex: (json['activeIndex'] as num?)?.toInt() ?? 0,
    rotation: (json['rotation'] as num?)?.toInt() ?? 0,
  );
}

class GameCounterRecord {
  GameCounterRecord({
    required this.time,
    required this.userId,
    required this.typeId,
    required this.delta,
    required this.value,
  });

  final DateTime time;
  final String userId;
  final String typeId;
  final int delta;
  final int value;

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'userId': userId,
    'typeId': typeId,
    'delta': delta,
    'value': value,
  };

  factory GameCounterRecord.fromJson(Map<String, dynamic> json) =>
      GameCounterRecord(
        time:
            DateTime.tryParse(json['time'] as String? ?? '') ?? DateTime.now(),
        userId: json['userId'] as String? ?? '',
        typeId: json['typeId'] as String? ?? '',
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        value: (json['value'] as num?)?.toInt() ?? 0,
      );
}

class GameScene {
  GameScene({
    required this.id,
    required this.name,
    List<GameCounterType>? types,
    List<GameUser>? users,
    Map<String, Map<String, int>>? values,
    List<GameCounterRecord>? history,
  }) : types = types ?? [],
       users = users ?? [],
       values = values ?? {},
       history = history ?? [];

  final String id;
  String name;
  final List<GameCounterType> types;
  final List<GameUser> users;
  final Map<String, Map<String, int>> values;
  final List<GameCounterRecord> history;

  static const maxHistory = 1000;

  GameCounterType? typeAt(int index) =>
      types.isEmpty ? null : types[index.clamp(0, types.length - 1)];

  GameCounterType? typeById(String? typeId) {
    for (final type in types) {
      if (type.id == typeId) return type;
    }
    return null;
  }

  GameUser? userById(String? userId) {
    for (final user in users) {
      if (user.id == userId) return user;
    }
    return null;
  }

  int valueFor(String userId, String typeId) {
    final stored = values[userId]?[typeId];
    if (stored != null) return stored;
    return typeById(typeId)?.defaultValue ?? 0;
  }

  void setValueFor(String userId, String typeId, int value) =>
      (values[userId] ??= {})[typeId] = value;

  void record(GameUser user, GameCounterType type, int delta) {
    if (delta == 0) return;
    history.add(
      GameCounterRecord(
        time: DateTime.now(),
        userId: user.id,
        typeId: type.id,
        delta: delta,
        value: valueFor(user.id, type.id),
      ),
    );
    if (history.length > maxHistory) {
      history.removeRange(0, history.length - maxHistory);
    }
  }

  void removeType(String typeId) {
    types.removeWhere((type) => type.id == typeId);
    for (final entry in values.values) {
      entry.remove(typeId);
    }
    history.removeWhere((item) => item.typeId == typeId);
    _clampActiveIndexes();
  }

  void removeUser(String userId) {
    users.removeWhere((user) => user.id == userId);
    values.remove(userId);
    history.removeWhere((item) => item.userId == userId);
  }

  void _clampActiveIndexes() {
    final last = types.isEmpty ? 0 : types.length - 1;
    for (final user in users) {
      if (user.activeIndex > last) user.activeIndex = last;
      if (user.activeIndex < 0) user.activeIndex = 0;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'types': types.map((type) => type.toJson()).toList(),
    'users': users.map((user) => user.toJson()).toList(),
    'values': values.map(
      (userId, byType) => MapEntry(userId, Map<String, int>.from(byType)),
    ),
    'history': history.map((item) => item.toJson()).toList(),
  };

  factory GameScene.fromJson(Map<String, dynamic> json) => GameScene(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    types: (json['types'] as List?)
        ?.whereType<Map>()
        .map(
          (entry) => GameCounterType.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(),
    users: (json['users'] as List?)
        ?.whereType<Map>()
        .map((entry) => GameUser.fromJson(Map<String, dynamic>.from(entry)))
        .toList(),
    values: (json['values'] as Map?)?.map(
      (userId, byType) => MapEntry(
        '$userId',
        (byType as Map?)?.map(
              (typeId, value) =>
                  MapEntry('$typeId', (value as num?)?.toInt() ?? 0),
            ) ??
            <String, int>{},
      ),
    ),
    history: (json['history'] as List?)
        ?.whereType<Map>()
        .map(
          (entry) =>
              GameCounterRecord.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(),
  );
}

class GameCounterData {
  GameCounterData({List<GameScene>? scenes, this.activeSceneId})
    : scenes = scenes ?? [];

  final List<GameScene> scenes;
  String? activeSceneId;
}

class GameCounterStore {
  GameCounterStore([this._directory]);
  static const _fileName = 'tool_game_counters.json';
  final Directory? _directory;
  File? _file;

  Future<File> _resolveFile() async {
    final cached = _file;
    if (cached != null) return cached;
    final directory = _directory ?? await getApplicationSupportDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$_fileName');
    _file = file;
    return file;
  }

  Future<GameCounterData> load() async {
    try {
      final file = await _resolveFile();
      if (!await file.exists()) return GameCounterData();
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return GameCounterData();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return GameCounterData();
      final scenes = (decoded['scenes'] as List?)
          ?.whereType<Map>()
          .map((entry) => GameScene.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
      return GameCounterData(
        scenes: scenes ?? [],
        activeSceneId: decoded['activeScene'] as String?,
      );
    } catch (_) {
      return GameCounterData();
    }
  }

  Future<void> save(GameCounterData data) async {
    try {
      final file = await _resolveFile();
      await file.writeAsString(
        jsonEncode({
          'activeScene': data.activeSceneId,
          'scenes': data.scenes.map((scene) => scene.toJson()).toList(),
        }),
        flush: true,
      );
    } catch (_) {}
  }
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    this.initial = '',
    this.hint,
  });

  final String title;
  final String label;
  final String initial;
  final String? hint;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, 'Cancel', '取消')),
      ),
      FilledButton(onPressed: _submit, child: Text(tr(context, 'Save', '保存'))),
    ],
  );
}

class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key});
  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  final _store = CounterStore();
  final _random = Random.secure();
  final _items = <CounterItem>[];
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _store.load();
    if (!mounted || _dirty || items.isEmpty) return;
    setState(() {
      _items
        ..clear()
        ..addAll(items);
    });
  }

  void _persist() {
    _dirty = true;
    unawaited(_store.save(_items));
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 31)}';

  static const _maxRecords = 500;

  void _record(CounterItem item, int delta) {
    if (delta == 0) return;
    item.records.add(
      CounterRecord(time: DateTime.now(), delta: delta, value: item.count),
    );
    if (item.records.length > _maxRecords) {
      item.records.removeRange(0, item.records.length - _maxRecords);
    }
  }

  Future<String?> _promptText({
    required String title,
    required String label,
    String initial = '',
    String? hint,
  }) => showDialog<String>(
    context: context,
    builder: (context) =>
        _PromptDialog(title: title, label: label, initial: initial, hint: hint),
  );

  Future<void> _add() async {
    final name = await _promptText(
      title: tr(context, 'New counter', '新建计数器'),
      label: tr(context, 'Event name', '事件名称'),
      hint: tr(context, 'e.g. Cups of coffee', '例如：喝了几杯咖啡'),
    );
    if (name == null || name.isEmpty) return;
    setState(() {
      _items.insert(
        0,
        CounterItem(
          id: _newId(),
          name: name,
          count: 0,
          updatedAt: DateTime.now(),
        ),
      );
    });
    _persist();
  }

  void _increment(CounterItem item) {
    setState(() {
      item.count += 1;
      item.updatedAt = DateTime.now();
      _record(item, 1);
    });
    _persist();
  }

  void _decrement(CounterItem item) {
    if (item.count <= 0) return;
    setState(() {
      item.count -= 1;
      item.updatedAt = DateTime.now();
      _record(item, -1);
    });
    _persist();
  }

  Future<void> _rename(CounterItem item) async {
    final name = await _promptText(
      title: tr(context, 'Rename counter', '重命名计数器'),
      label: tr(context, 'Event name', '事件名称'),
      initial: item.name,
    );
    if (name == null || name.isEmpty) return;
    setState(() {
      item.name = name;
      item.updatedAt = DateTime.now();
    });
    _persist();
  }

  Future<void> _editValue(CounterItem item) async {
    final value = await _promptText(
      title: tr(context, 'Set count', '设置计数'),
      label: tr(context, 'Count', '计数'),
      initial: '${item.count}',
    );
    if (value == null) return;
    final parsed = int.tryParse(value);
    if (parsed == null) return;
    setState(() {
      final delta = parsed - item.count;
      item.count = parsed;
      item.updatedAt = DateTime.now();
      _record(item, delta);
    });
    _persist();
  }

  void _reset(CounterItem item) {
    if (item.count == 0) return;
    setState(() {
      final delta = -item.count;
      item.count = 0;
      item.updatedAt = DateTime.now();
      _record(item, delta);
    });
    _persist();
  }

  Future<void> _delete(CounterItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Delete counter', '删除计数器')),
        content: Text(
          tr(
            context,
            'Delete "${item.name}"? This cannot be undone.',
            '删除“${item.name}”？此操作无法撤销。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Delete', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _items.remove(item));
    _persist();
  }

  void _openHistory(CounterItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CounterHistoryScreen(item: item, onChanged: _persist),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<int>(0, (sum, item) => sum + item.count);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, '+1 Counter', '+1 计数器')),
        actions: [toolInfoAction(context, 'counter')],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'New counter', '新建计数器')),
      ),
      body: Column(
        children: [
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(context, 'Counters', '计数器'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    tr(context, 'Total: $total', '总计：$total'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _items.isEmpty
                ? const _EmptyCounters()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                    itemCount: _items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return _CounterCard(
                        item: item,
                        onIncrement: () => _increment(item),
                        onDecrement: () => _decrement(item),
                        onHistory: () => _openHistory(item),
                        onRename: () => _rename(item),
                        onEditValue: () => _editValue(item),
                        onReset: () => _reset(item),
                        onDelete: () => _delete(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  const _CounterCard({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onHistory,
    required this.onRename,
    required this.onEditValue,
    required this.onReset,
    required this.onDelete,
  });

  final CounterItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onHistory;
  final VoidCallback onRename;
  final VoidCallback onEditValue;
  final VoidCallback onReset;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.name,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: tr(context, 'History', '计数记录'),
                  onPressed: onHistory,
                  icon: const Icon(Icons.history),
                ),
                PopupMenuButton<String>(
                  tooltip: tr(context, 'Counter actions', '计数器操作'),
                  onSelected: (value) {
                    switch (value) {
                      case 'history':
                        onHistory();
                      case 'rename':
                        onRename();
                      case 'value':
                        onEditValue();
                      case 'reset':
                        onReset();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'history',
                      child: Text(tr(context, 'History', '计数记录')),
                    ),
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(tr(context, 'Rename', '重命名')),
                    ),
                    PopupMenuItem(
                      value: 'value',
                      child: Text(tr(context, 'Set count', '设置计数')),
                    ),
                    PopupMenuItem(
                      value: 'reset',
                      child: Text(tr(context, 'Reset to zero', '归零')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(tr(context, 'Delete', '删除')),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: tr(context, 'Decrease by one', '减一'),
                  onPressed: item.count <= 0 ? null : onDecrement,
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onIncrement,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text(
                            '${item.count}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.displaySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            tr(context, 'Tap to add one', '轻点加一'),
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton.filled(
                  tooltip: tr(context, 'Add one', '加一'),
                  onPressed: onIncrement,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CounterHistoryScreen extends StatefulWidget {
  const CounterHistoryScreen({
    super.key,
    required this.item,
    required this.onChanged,
  });

  final CounterItem item;
  final VoidCallback onChanged;

  @override
  State<CounterHistoryScreen> createState() => _CounterHistoryScreenState();
}

class _CounterHistoryScreenState extends State<CounterHistoryScreen> {
  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Clear records', '清除记录')),
        content: Text(
          tr(
            context,
            'Clear all records for "${widget.item.name}"?',
            '清除“${widget.item.name}”的全部记录？',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Clear', '清除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.item.records.clear();
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.item.records;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Counter history', '计数记录')),
        actions: [
          if (records.isNotEmpty)
            IconButton(
              tooltip: tr(context, 'Clear records', '清除记录'),
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: records.isEmpty
          ? Center(
              child: Text(
                tr(context, 'No records yet.', '还没有记录。'),
                style: theme.textTheme.titleMedium,
              ),
            )
          : ListView.separated(
              itemCount: records.length + 1,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return ListTile(
                    dense: true,
                    title: Text(
                      widget.item.name,
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      tr(
                        context,
                        'Current: ${widget.item.count}',
                        '当前：${widget.item.count}',
                      ),
                    ),
                  );
                }
                final record = records[records.length - index];
                final positive = record.delta > 0;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: positive
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.errorContainer,
                    foregroundColor: positive
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onErrorContainer,
                    child: Text(
                      positive ? '+${record.delta}' : '${record.delta}',
                    ),
                  ),
                  title: Text(formatTimestamp(record.time)),
                  subtitle: Text(
                    tr(
                      context,
                      'Total after: ${record.value}',
                      '变更后：${record.value}',
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyCounters extends StatelessWidget {
  const _EmptyCounters();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.exposure_plus_1_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            tr(context, 'No counters yet', '还没有计数器'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              'Create a counter for any custom event, then tap to add one.',
              '为任意自定义事件创建计数器，轻点即可加一。',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

String newGameId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';

class GameCounterScreen extends StatefulWidget {
  const GameCounterScreen({super.key});
  @override
  State<GameCounterScreen> createState() => _GameCounterScreenState();
}

class _GameCounterScreenState extends State<GameCounterScreen> {
  final _store = GameCounterStore();
  final _data = GameCounterData();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _ensureDefaultScene();
    _load();
  }

  void _ensureDefaultScene() {
    if (_data.scenes.isNotEmpty) return;
    final scene = GameScene(
      id: newGameId(),
      name: tr(context, 'Game 1', '游戏 1'),
      types: [
        GameCounterType(id: newGameId(), name: tr(context, 'Score', '计分')),
      ],
      users: [
        GameUser(id: newGameId()),
        GameUser(id: newGameId()),
      ],
    );
    _data.scenes.add(scene);
    _data.activeSceneId = scene.id;
  }

  Future<void> _load() async {
    final loaded = await _store.load();
    if (!mounted) return;
    if (loaded.scenes.isEmpty) {
      unawaited(_store.save(_data));
      return;
    }
    setState(() {
      _data.scenes
        ..clear()
        ..addAll(loaded.scenes);
      _data.activeSceneId = loaded.activeSceneId;
    });
  }

  void _persist([GameCounterData? _]) {
    unawaited(_store.save(_data));
  }

  GameScene? get _activeScene {
    if (_data.scenes.isEmpty) return null;
    return _data.scenes.firstWhere(
      (scene) => scene.id == _data.activeSceneId,
      orElse: () => _data.scenes.first,
    );
  }

  void _selectScene(GameScene scene) {
    setState(() => _data.activeSceneId = scene.id);
    _persist();
  }

  String _userLabel(GameScene scene, GameUser user) =>
      user.name.isEmpty ? 'P${scene.users.indexOf(user) + 1}' : user.name;

  void _bump(GameScene scene, GameUser user, int delta) {
    final type = scene.typeAt(user.activeIndex);
    if (type == null) return;
    setState(() {
      final current = scene.valueFor(user.id, type.id);
      final next = (current + delta).clamp(0, 1 << 31);
      scene.setValueFor(user.id, type.id, next);
      scene.record(user, type, next - current);
    });
    _persist();
  }

  void _reset(GameScene scene, GameUser user) {
    final type = scene.typeAt(user.activeIndex);
    if (type == null) return;
    final current = scene.valueFor(user.id, type.id);
    if (current == type.defaultValue) return;
    setState(() {
      scene.setValueFor(user.id, type.id, type.defaultValue);
      scene.record(user, type, type.defaultValue - current);
    });
    _persist();
  }

  void _setActive(GameScene scene, GameUser user, int index) {
    if (user.activeIndex == index) return;
    setState(() => user.activeIndex = index);
    _persist();
  }

  void _rotate(GameUser user) {
    setState(() => user.rotation = (user.rotation + 1) % 4);
    _persist();
  }

  Future<void> _resetAll(GameScene scene) async {
    var hasValue = false;
    for (final user in scene.users) {
      for (final type in scene.types) {
        if (scene.valueFor(user.id, type.id) != type.defaultValue) {
          hasValue = true;
          break;
        }
      }
      if (hasValue) break;
    }
    if (!hasValue) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Reset all counters', '所有计数器清零')),
        content: Text(
          tr(
            context,
            'Reset every counter in "${scene.name}" to its default value?',
            '将“${scene.name}”的所有计数器重置为默认值？',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Reset', '清零')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      for (final user in scene.users) {
        for (final type in scene.types) {
          final current = scene.valueFor(user.id, type.id);
          if (current == type.defaultValue) continue;
          scene.setValueFor(user.id, type.id, type.defaultValue);
          scene.record(user, type, type.defaultValue - current);
        }
      }
    });
    _persist();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            GameCounterSettingsScreen(data: _data, onChanged: _persist),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  void _openHistory(GameScene scene) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            GameCounterHistoryScreen(scene: scene, onChanged: _persist),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scene = _activeScene;
    return Scaffold(
      appBar: AppBar(
        title: _SceneSelector(
          sceneName: scene?.name ?? tr(context, 'Game Counter', '游戏计数器'),
          scenes: _data.scenes,
          activeId: scene?.id,
          onSelect: _selectScene,
          onManage: _openSettings,
        ),
        actions: [
          IconButton(
            tooltip: tr(context, 'Reset all counters', '所有计数器清零'),
            onPressed: scene == null ? null : () => _resetAll(scene),
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: tr(context, 'History', '历史记录'),
            onPressed: scene == null ? null : () => _openHistory(scene),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: tr(context, 'Settings', '设置'),
            onPressed: _openSettings,
            icon: const Icon(Icons.tune),
          ),
          toolInfoAction(context, 'game-counter'),
        ],
      ),
      body: scene == null || scene.users.isEmpty
          ? _EmptyGamePanels(onAdd: _openSettings)
          : _UsersGrid(
              scene: scene,
              userLabel: (user) => _userLabel(scene, user),
              onBump: (user, delta) => _bump(scene, user, delta),
              onReset: (user) => _reset(scene, user),
              onSetActive: (user, index) => _setActive(scene, user, index),
              onRotate: _rotate,
            ),
    );
  }
}

class _SceneSelector extends StatelessWidget {
  const _SceneSelector({
    required this.sceneName,
    required this.scenes,
    required this.activeId,
    required this.onSelect,
    required this.onManage,
  });

  final String sceneName;
  final List<GameScene> scenes;
  final String? activeId;
  final ValueChanged<GameScene> onSelect;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: tr(context, 'Switch scene', '切换场景'),
    onSelected: (value) {
      if (value == '__manage__') {
        onManage();
        return;
      }
      for (final scene in scenes) {
        if (scene.id == value) {
          onSelect(scene);
          return;
        }
      }
    },
    itemBuilder: (context) => [
      for (final scene in scenes)
        PopupMenuItem(
          value: scene.id,
          child: Row(
            children: [
              Icon(
                scene.id == activeId ? Icons.check : Icons.circle_outlined,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(scene.name, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: '__manage__',
        child: Text(tr(context, 'Manage scenes…', '管理场景…')),
      ),
    ],
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            sceneName,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Icon(Icons.arrow_drop_down),
      ],
    ),
  );
}

class _UsersGrid extends StatelessWidget {
  const _UsersGrid({
    required this.scene,
    required this.userLabel,
    required this.onBump,
    required this.onReset,
    required this.onSetActive,
    required this.onRotate,
  });

  final GameScene scene;
  final String Function(GameUser user) userLabel;
  final void Function(GameUser user, int delta) onBump;
  final void Function(GameUser user) onReset;
  final void Function(GameUser user, int index) onSetActive;
  final void Function(GameUser user) onRotate;

  int _columns(int count, double width) {
    if (count <= 1) return 1;
    if (count == 2) return width >= 720 ? 2 : 1;
    if (count <= 4) return 2;
    if (count <= 6) return width >= 720 ? 3 : 2;
    return width >= 960 ? 4 : (width >= 640 ? 3 : 2);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 12.0;
      final users = scene.users;
      final count = users.length;
      final columns = _columns(count, constraints.maxWidth);
      final rows = (count / columns).ceil();
      final fitHeight = (constraints.maxHeight - spacing * (rows - 1)) / rows;
      final tileHeight = fitHeight < 150 ? 150.0 : fitHeight;
      final tileWidth =
          (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: spacing,
          crossAxisSpacing: spacing,
          childAspectRatio: tileWidth / tileHeight,
        ),
        itemCount: count,
        itemBuilder: (context, index) {
          final user = users[index];
          return _GameUserCard(
            key: ValueKey(user.id),
            scene: scene,
            user: user,
            label: userLabel(user),
            onBump: (delta) => onBump(user, delta),
            onReset: () => onReset(user),
            onSetActive: (activeIndex) => onSetActive(user, activeIndex),
            onRotate: () => onRotate(user),
          );
        },
      );
    },
  );
}

class _GameUserCard extends StatefulWidget {
  const _GameUserCard({
    super.key,
    required this.scene,
    required this.user,
    required this.label,
    required this.onBump,
    required this.onReset,
    required this.onSetActive,
    required this.onRotate,
  });

  final GameScene scene;
  final GameUser user;
  final String label;
  final ValueChanged<int> onBump;
  final VoidCallback onReset;
  final ValueChanged<int> onSetActive;
  final VoidCallback onRotate;

  @override
  State<_GameUserCard> createState() => _GameUserCardState();
}

class _GameUserCardState extends State<_GameUserCard> {
  late final PageController _controller = PageController(
    initialPage: widget.user.activeIndex.clamp(0, _lastIndex),
  );

  int get _lastIndex =>
      widget.scene.types.isEmpty ? 0 : widget.scene.types.length - 1;

  @override
  void didUpdateWidget(covariant _GameUserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.hasClients &&
        _controller.page?.round() != widget.user.activeIndex) {
      _controller.animateToPage(
        widget.user.activeIndex.clamp(0, _lastIndex),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = widget.scene.types;
    final user = widget.user;
    final activeType = widget.scene.typeAt(user.activeIndex);
    Widget content = Card(
      clipBehavior: Clip.antiAlias,
      child: activeType == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr(
                    context,
                    'Add counter types in settings.',
                    '请在设置中添加计数器类型。',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Column(
              children: [
                _UserTopBar(
                  label: widget.label,
                  onRotate: widget.onRotate,
                  onReset: widget.onReset,
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    onPageChanged: widget.onSetActive,
                    itemCount: types.length,
                    itemBuilder: (context, index) => _UserCounterPage(
                      value: widget.scene.valueFor(user.id, types[index].id),
                      quickDirection: types[index].quickDirection,
                      onBump: widget.onBump,
                    ),
                  ),
                ),
                _UserTypeTabs(
                  types: types,
                  activeIndex: user.activeIndex,
                  onSelect: widget.onSetActive,
                ),
              ],
            ),
    );
    if (user.rotation % 4 != 0) {
      content = RotatedBox(quarterTurns: user.rotation % 4, child: content);
    }
    return content;
  }
}

class _UserTopBar extends StatelessWidget {
  const _UserTopBar({
    required this.label,
    required this.onRotate,
    required this.onReset,
  });

  final String label;
  final VoidCallback onRotate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 8),
        Chip(
          avatar: const Icon(Icons.person_outline, size: 16),
          label: Text(label, overflow: TextOverflow.ellipsis),
          visualDensity: VisualDensity.compact,
        ),
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: tr(context, 'Panel actions', '面板操作'),
          onSelected: (value) {
            switch (value) {
              case 'rotate':
                onRotate();
              case 'reset':
                onReset();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'rotate',
              child: Text(tr(context, 'Rotate 90°', '旋转 90°')),
            ),
            PopupMenuItem(
              value: 'reset',
              child: Text(tr(context, 'Reset to zero', '归零')),
            ),
          ],
        ),
      ],
    );
  }
}

class _UserTypeTabs extends StatelessWidget {
  const _UserTypeTabs({
    required this.types,
    required this.activeIndex,
    required this.onSelect,
  });

  final List<GameCounterType> types;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 8),
        itemCount: types.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) => ChoiceChip(
          label: Text(types[index].name),
          selected: index == activeIndex,
          onSelected: (_) => onSelect(index),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _UserCounterPage extends StatelessWidget {
  const _UserCounterPage({
    required this.value,
    required this.quickDirection,
    required this.onBump,
  });

  final int value;
  final int quickDirection;
  final ValueChanged<int> onBump;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: tr(context, 'Decrease by one', '减一'),
            onPressed: value <= 0 ? null : () => onBump(-1),
            icon: const Icon(Icons.remove),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onBump(quickDirection),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$value',
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton.filled(
            tooltip: tr(context, 'Add one', '加一'),
            onPressed: () => onBump(1),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

class _EmptyGamePanels extends StatelessWidget {
  const _EmptyGamePanels({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sports_esports_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            tr(context, 'No players yet', '还没有玩家'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              context,
              'Open settings to add players and counter types for your game.',
              '打开设置，为你的游戏添加玩家和计数器类型。',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text(tr(context, 'Open settings', '打开设置')),
          ),
        ],
      ),
    ),
  );
}

class GameCounterHistoryScreen extends StatefulWidget {
  const GameCounterHistoryScreen({
    super.key,
    required this.scene,
    required this.onChanged,
  });

  final GameScene scene;
  final VoidCallback onChanged;

  @override
  State<GameCounterHistoryScreen> createState() =>
      _GameCounterHistoryScreenState();
}

class _GameCounterHistoryScreenState extends State<GameCounterHistoryScreen> {
  GameScene get _scene => widget.scene;

  Future<void> _clear() async {
    if (_scene.history.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Clear records', '清除记录')),
        content: Text(
          tr(
            context,
            'Clear the history for "${_scene.name}"?',
            '清除“${_scene.name}”的历史记录？',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Clear', '清除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _scene.history.clear());
    widget.onChanged();
  }

  String _userLabel(String userId) {
    final index = _scene.users.indexWhere((user) => user.id == userId);
    if (index < 0) {
      return tr(context, 'Removed player', '已移除的玩家');
    }
    final user = _scene.users[index];
    return user.name.isEmpty
        ? tr(context, 'P${index + 1}', 'P${index + 1}')
        : user.name;
  }

  @override
  Widget build(BuildContext context) {
    final records = _scene.history.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'History', '历史记录')),
        actions: [
          IconButton(
            tooltip: tr(context, 'Clear records', '清除记录'),
            onPressed: records.isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: records.isEmpty
          ? Center(
              child: Text(
                tr(context, 'No records yet', '还没有记录'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: records.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final record = records[index];
                final typeName =
                    _scene.typeById(record.typeId)?.name ??
                    tr(context, 'Removed counter', '已移除的计数器');
                final sign = record.delta > 0 ? '+' : '';
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    child: Text(
                      _userLabel(record.userId),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  title: Text('$typeName  $sign${record.delta}'),
                  subtitle: Text(formatTimestamp(record.time)),
                  trailing: Text(
                    '${record.value}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              },
            ),
    );
  }
}

class GameCounterSettingsScreen extends StatefulWidget {
  const GameCounterSettingsScreen({
    super.key,
    required this.data,
    required this.onChanged,
  });

  final GameCounterData data;
  final ValueChanged<GameCounterData> onChanged;

  @override
  State<GameCounterSettingsScreen> createState() =>
      _GameCounterSettingsScreenState();
}

class _GameCounterSettingsScreenState extends State<GameCounterSettingsScreen> {
  GameCounterData get _data => widget.data;

  void _changed() {
    widget.onChanged(_data);
    setState(() {});
  }

  Future<String?> _prompt({
    required String title,
    required String label,
    String initial = '',
  }) => showDialog<String>(
    context: context,
    builder: (context) =>
        _PromptDialog(title: title, label: label, initial: initial),
  );

  GameScene _ensureScene() {
    if (_data.scenes.isEmpty) {
      final scene = GameScene(
        id: newGameId(),
        name: tr(context, 'Game 1', '游戏 1'),
      );
      _data.scenes.add(scene);
      _data.activeSceneId = scene.id;
    }
    _data.activeSceneId ??= _data.scenes.first.id;
    return _data.scenes.firstWhere(
      (scene) => scene.id == _data.activeSceneId,
      orElse: () => _data.scenes.first,
    );
  }

  Future<void> _addScene() async {
    final name = await _prompt(
      title: tr(context, 'New scene', '新建场景'),
      label: tr(context, 'Scene name', '场景名称'),
      initial: tr(
        context,
        'Game ${_data.scenes.length + 1}',
        '游戏 ${_data.scenes.length + 1}',
      ),
    );
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    final scene = GameScene(
      id: newGameId(),
      name: name,
      types: [
        GameCounterType(id: newGameId(), name: tr(context, 'Score', '计分')),
      ],
      users: [
        GameUser(id: newGameId()),
        GameUser(id: newGameId()),
      ],
    );
    _data.scenes.add(scene);
    _data.activeSceneId = scene.id;
    _changed();
  }

  Future<void> _renameScene(GameScene scene) async {
    final name = await _prompt(
      title: tr(context, 'Rename scene', '重命名场景'),
      label: tr(context, 'Scene name', '场景名称'),
      initial: scene.name,
    );
    if (name == null || name.isEmpty) return;
    scene.name = name;
    _changed();
  }

  Future<void> _deleteScene(GameScene scene) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Delete scene', '删除场景')),
        content: Text(
          tr(
            context,
            'Delete "${scene.name}" and all its players?',
            '删除“${scene.name}”及其所有玩家？',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Delete', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _data.scenes.remove(scene);
    if (_data.activeSceneId == scene.id) {
      _data.activeSceneId = _data.scenes.isEmpty ? null : _data.scenes.first.id;
    }
    _changed();
  }

  Future<void> _addType(GameScene scene) async {
    final name = await _prompt(
      title: tr(context, 'New counter type', '新建计数器类型'),
      label: tr(context, 'Counter name', '计数器名称'),
      initial: tr(
        context,
        'Counter ${scene.types.length + 1}',
        '计数器 ${scene.types.length + 1}',
      ),
    );
    if (name == null || name.isEmpty) return;
    scene.types.add(GameCounterType(id: newGameId(), name: name));
    _changed();
  }

  Future<void> _renameType(GameScene scene, GameCounterType type) async {
    final name = await _prompt(
      title: tr(context, 'Rename counter type', '重命名计数器类型'),
      label: tr(context, 'Counter name', '计数器名称'),
      initial: type.name,
    );
    if (name == null || name.isEmpty) return;
    type.name = name;
    _changed();
  }

  Future<void> _editDefaultValue(GameCounterType type) async {
    final value = await _prompt(
      title: tr(context, 'Default value', '默认值'),
      label: tr(context, 'Counter default', '计数器默认值'),
      initial: '${type.defaultValue}',
    );
    if (value == null) return;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    setState(() => type.defaultValue = parsed);
    _changed();
  }

  Future<void> _removeType(GameScene scene, GameCounterType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Delete counter type', '删除计数器类型')),
        content: Text(
          tr(
            context,
            'Delete "${type.name}"? Its history will be discarded.',
            '删除“${type.name}”？其历史记录将被废弃。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr(context, 'Cancel', '取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr(context, 'Delete', '删除')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    scene.removeType(type.id);
    _changed();
  }

  Future<void> _setUserCount(GameScene scene, int count) async {
    final target = count.clamp(1, 24);
    setState(() {
      while (scene.users.length > target) {
        scene.removeUser(scene.users.last.id);
      }
      while (scene.users.length < target) {
        scene.users.add(GameUser(id: newGameId()));
      }
    });
    _changed();
  }

  Future<void> _editUserCount(GameScene scene) async {
    final value = await _prompt(
      title: tr(context, 'Number of players', '玩家数量'),
      label: tr(context, 'Players', '玩家'),
      initial: '${scene.users.length}',
    );
    if (value == null) return;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return;
    await _setUserCount(scene, parsed);
  }

  Future<void> _renameUser(GameScene scene, GameUser user, int index) async {
    final name = await _prompt(
      title: tr(context, 'Rename player', '重命名玩家'),
      label: tr(context, 'Player name', '玩家名称'),
      initial: user.name,
    );
    if (name == null) return;
    setState(() => user.name = name.trim());
    _changed();
  }

  void _resetScene(GameScene scene) {
    setState(() {
      for (final user in scene.users) {
        scene.values[user.id] = {};
      }
      scene.history.clear();
    });
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _ensureScene();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Game counter settings', '游戏计数器设置')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            tr(context, 'Scenes', '场景'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in _data.scenes)
                ChoiceChip(
                  label: Text(item.name),
                  selected: item.id == scene.id,
                  onSelected: (_) {
                    _data.activeSceneId = item.id;
                    _changed();
                  },
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(tr(context, 'New scene', '新建场景')),
                onPressed: _addScene,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _renameScene(scene),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(tr(context, 'Rename scene', '重命名场景')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _resetScene(scene),
                  icon: const Icon(Icons.restart_alt),
                  label: Text(tr(context, 'Reset scene', '场景归零')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: tr(context, 'Delete scene', '删除场景'),
                onPressed: _data.scenes.length <= 1
                    ? null
                    : () => _deleteScene(scene),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, 'Counter types', '计数器类型'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => _addType(scene),
                icon: const Icon(Icons.add),
                label: Text(tr(context, 'Add type', '添加类型')),
              ),
            ],
          ),
          Text(
            tr(
              context,
              'These counters are shared by every player, like health or mana.',
              '这些计数器由所有玩家共享，例如血量或魔法值。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (scene.types.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                tr(
                  context,
                  'No counter types yet. Add one to start counting.',
                  '还没有计数器类型，添加一个开始计数。',
                ),
              ),
            ),
          for (final type in scene.types)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.tag),
              title: Text(type.name),
              subtitle: Text(
                '${type.quickDirection > 0 ? tr(context, 'Quick tap: +1', '轻点方向：+1') : tr(context, 'Quick tap: -1', '轻点方向：-1')}'
                ' · ${tr(context, 'Default: ${type.defaultValue}', '默认值：${type.defaultValue}')}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: tr(context, 'Set default value', '设置默认值'),
                    onPressed: () => _editDefaultValue(type),
                    icon: const Icon(Icons.exposure_zero),
                  ),
                  IconButton(
                    tooltip: tr(
                      context,
                      'Toggle quick tap direction',
                      '切换轻点方向',
                    ),
                    onPressed: () {
                      setState(
                        () => type.quickDirection = type.quickDirection > 0
                            ? -1
                            : 1,
                      );
                      _changed();
                    },
                    icon: Icon(
                      type.quickDirection > 0
                          ? Icons.add_circle_outline
                          : Icons.remove_circle_outline,
                    ),
                  ),
                  IconButton(
                    tooltip: tr(context, 'Rename', '重命名'),
                    onPressed: () => _renameType(scene, type),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: tr(context, 'Delete', '删除'),
                    onPressed: scene.types.length <= 1
                        ? null
                        : () => _removeType(scene, type),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(context, 'Players', '玩家'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${scene.users.length}',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
              IconButton(
                tooltip: tr(context, 'Decrease', '减少'),
                onPressed: scene.users.length <= 1
                    ? null
                    : () => _setUserCount(scene, scene.users.length - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                tooltip: tr(context, 'Increase', '增加'),
                onPressed: scene.users.length >= 24
                    ? null
                    : () => _setUserCount(scene, scene.users.length + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                tooltip: tr(context, 'Set number of players', '设置玩家数量'),
                onPressed: () => _editUserCount(scene),
                icon: const Icon(Icons.numbers),
              ),
            ],
          ),
          Text(
            tr(
              context,
              'Each player gets a panel on the main screen.',
              '每位玩家在主界面都有一个面板。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          for (var i = 0; i < scene.users.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(
                scene.users[i].name.isEmpty
                    ? tr(context, 'Player ${i + 1}', '玩家 ${i + 1}')
                    : scene.users[i].name,
              ),
              trailing: IconButton(
                tooltip: tr(context, 'Rename', '重命名'),
                onPressed: () => _renameUser(scene, scene.users[i], i),
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
        ],
      ),
    );
  }
}

enum BaseVariant { base16, base32, base58, base64, base64Url }

class BaseCodec {
  static const _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  static const _base58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  static String encode(BaseVariant variant, List<int> bytes) =>
      switch (variant) {
        BaseVariant.base16 => _hexEncode(bytes),
        BaseVariant.base32 => _base32Encode(bytes),
        BaseVariant.base58 => _base58Encode(bytes),
        BaseVariant.base64 => base64Encode(bytes),
        BaseVariant.base64Url => base64UrlEncode(bytes),
      };

  static List<int> decode(BaseVariant variant, String text) =>
      switch (variant) {
        BaseVariant.base16 => _hexDecode(text),
        BaseVariant.base32 => _base32Decode(text),
        BaseVariant.base58 => _base58Decode(text),
        BaseVariant.base64 => base64Decode(_stripWhitespace(text)),
        BaseVariant.base64Url => base64Url.decode(
          base64Url.normalize(_stripWhitespace(text)),
        ),
      };

  static String _stripWhitespace(String text) =>
      text.replaceAll(RegExp(r'\s+'), '');

  static String _hexEncode(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _hexDecode(String text) {
    final cleaned = _stripWhitespace(text).toLowerCase();
    if (cleaned.length.isOdd) {
      throw const FormatException('Base16 input must have an even length');
    }
    final result = <int>[];
    for (var index = 0; index < cleaned.length; index += 2) {
      final byte = int.tryParse(cleaned.substring(index, index + 2), radix: 16);
      if (byte == null) {
        throw const FormatException('Invalid Base16 character');
      }
      result.add(byte);
    }
    return result;
  }

  static String _base32Encode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    final buffer = StringBuffer();
    var bits = 0;
    var value = 0;
    for (final byte in bytes) {
      value = (value << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        buffer.write(_base32Alphabet[(value >> (bits - 5)) & 0x1f]);
        bits -= 5;
      }
    }
    if (bits > 0) {
      buffer.write(_base32Alphabet[(value << (5 - bits)) & 0x1f]);
    }
    while (buffer.length % 8 != 0) {
      buffer.write('=');
    }
    return buffer.toString();
  }

  static List<int> _base32Decode(String text) {
    final cleaned = _stripWhitespace(text).toUpperCase().replaceAll('=', '');
    final result = <int>[];
    var bits = 0;
    var value = 0;
    for (final character in cleaned.split('')) {
      final index = _base32Alphabet.indexOf(character);
      if (index < 0) {
        throw const FormatException('Invalid Base32 character');
      }
      value = (value << 5) | index;
      bits += 5;
      if (bits >= 8) {
        result.add((value >> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    return result;
  }

  static String _base58Encode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    var zeros = 0;
    while (zeros < bytes.length && bytes[zeros] == 0) {
      zeros++;
    }
    final digits = <int>[];
    for (var index = zeros; index < bytes.length; index++) {
      var carry = bytes[index];
      for (var digit = 0; digit < digits.length; digit++) {
        carry += digits[digit] << 8;
        digits[digit] = carry % 58;
        carry ~/= 58;
      }
      while (carry > 0) {
        digits.add(carry % 58);
        carry ~/= 58;
      }
    }
    final buffer = StringBuffer();
    for (var index = 0; index < zeros; index++) {
      buffer.write(_base58Alphabet[0]);
    }
    for (var index = digits.length - 1; index >= 0; index--) {
      buffer.write(_base58Alphabet[digits[index]]);
    }
    return buffer.toString();
  }

  static List<int> _base58Decode(String text) {
    final cleaned = _stripWhitespace(text);
    if (cleaned.isEmpty) return [];
    var zeros = 0;
    while (zeros < cleaned.length && cleaned[zeros] == _base58Alphabet[0]) {
      zeros++;
    }
    final bytes = <int>[];
    for (var index = zeros; index < cleaned.length; index++) {
      final value = _base58Alphabet.indexOf(cleaned[index]);
      if (value < 0) {
        throw const FormatException('Invalid Base58 character');
      }
      var carry = value;
      for (var byte = 0; byte < bytes.length; byte++) {
        carry += bytes[byte] * 58;
        bytes[byte] = carry & 0xff;
        carry >>= 8;
      }
      while (carry > 0) {
        bytes.add(carry & 0xff);
        carry >>= 8;
      }
    }
    final result = <int>[];
    for (var index = 0; index < zeros; index++) {
      result.add(0);
    }
    for (var index = bytes.length - 1; index >= 0; index--) {
      result.add(bytes[index]);
    }
    return result;
  }
}

class BaseCodecScreen extends StatefulWidget {
  const BaseCodecScreen({super.key});
  @override
  State<BaseCodecScreen> createState() => _BaseCodecScreenState();
}

class _BaseCodecScreenState extends State<BaseCodecScreen> {
  final _input = TextEditingController();
  final _output = TextEditingController();
  BaseVariant _variant = BaseVariant.base64;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    _output.dispose();
    super.dispose();
  }

  static String _variantLabel(BaseVariant variant) => switch (variant) {
    BaseVariant.base16 => 'Base16',
    BaseVariant.base32 => 'Base32',
    BaseVariant.base58 => 'Base58',
    BaseVariant.base64 => 'Base64',
    BaseVariant.base64Url => 'Base64 URL',
  };

  void _encode() {
    setState(() {
      try {
        _output.text = BaseCodec.encode(_variant, utf8.encode(_input.text));
        _error = null;
      } on FormatException {
        _output.text = '';
        _error = tr(
          context,
          'Invalid input for the selected base.',
          '输入不符合所选进制。',
        );
      }
    });
  }

  void _decode() {
    setState(() {
      try {
        _output.text = utf8.decode(BaseCodec.decode(_variant, _input.text));
        _error = null;
      } on FormatException {
        _output.text = '';
        _error = tr(
          context,
          'Invalid input for the selected base.',
          '输入不符合所选进制。',
        );
      }
    });
  }

  void _swap() {
    setState(() {
      final previous = _output.text;
      _output.text = _input.text;
      _input.text = previous;
      _error = null;
    });
  }

  void _clear() {
    setState(() {
      _input.clear();
      _output.clear();
      _error = null;
    });
  }

  Future<void> _copy() async {
    if (_output.text.isEmpty) return;
    final message = tr(context, 'Copied', '已复制');
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _output.text));
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Basexx', 'Base 编解码')),
        actions: [toolInfoAction(context, 'basexx')],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr(context, 'Base', '进制'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: BaseVariant.values
                      .map(
                        (variant) => ChoiceChip(
                          label: Text(_variantLabel(variant)),
                          selected: _variant == variant,
                          onSelected: (_) => setState(() => _variant = variant),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _input,
                  minLines: 3,
                  maxLines: 8,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: tr(context, 'Input', '输入'),
                    hintText: tr(
                      context,
                      'Enter text or an encoded value',
                      '输入文本或编码值',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _encode,
                        child: Text(tr(context, 'Encode', '编码')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: _decode,
                        child: Text(tr(context, 'Decode', '解码')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _swap,
                        icon: const Icon(Icons.swap_vert),
                        label: Text(tr(context, 'Swap', '互换')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _clear,
                        icon: const Icon(Icons.clear),
                        label: Text(tr(context, 'Clear', '清空')),
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _output,
                  readOnly: true,
                  minLines: 3,
                  maxLines: 8,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: tr(context, 'Output', '输出'),
                    hintText: tr(context, 'Result appears here', '结果会显示在这里'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _output.text.isEmpty ? null : _copy,
                    icon: const Icon(Icons.copy),
                    label: Text(tr(context, 'Copy', '复制')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum Direction2048 { up, down, left, right }

enum Game2048Mode {
  mini(3, 256, '3 × 3'),
  classic(4, 2048, '4 × 4'),
  large(5, 4096, '5 × 5'),
  huge(6, 8192, '6 × 6');

  const Game2048Mode(this.size, this.target, this.label);
  final int size;
  final int target;
  final String label;
}

class Game2048 {
  Game2048({Random? random, this.size = 4, this.target = 2048})
    : _random = random ?? Random() {
    cells = List<int>.filled(size * size, 0);
  }

  Game2048.withCells(
    this.cells, {
    this.size = 4,
    this.target = 2048,
    Random? random,
  }) : _random = random ?? Random();

  final int size;
  final int target;
  late final List<int> cells;
  final Random _random;
  int score = 0;

  void reset() {
    for (var index = 0; index < cells.length; index++) {
      cells[index] = 0;
    }
    score = 0;
    _spawn();
    _spawn();
  }

  bool get hasMoves {
    for (var index = 0; index < cells.length; index++) {
      if (cells[index] == 0) return true;
      final row = index ~/ size;
      final column = index % size;
      if (column + 1 < size && cells[index] == cells[index + 1]) {
        return true;
      }
      if (row + 1 < size && cells[index] == cells[index + size]) {
        return true;
      }
    }
    return false;
  }

  bool move(Direction2048 direction, {bool spawn = true}) {
    final before = List<int>.of(cells);
    var gained = 0;
    for (final line in _lines(size, direction)) {
      final values = line.map((index) => cells[index]).toList();
      final collapsed = _collapse(values, (value) => gained += value);
      for (var index = 0; index < line.length; index++) {
        cells[line[index]] = collapsed[index];
      }
    }
    if (listEquals(before, cells)) return false;
    score += gained;
    if (spawn) _spawn();
    return true;
  }

  static List<int> slideBoard(List<int> cells, Direction2048 direction) {
    final size = sqrt(cells.length).round();
    final result = List<int>.of(cells);
    for (final line in _lines(size, direction)) {
      final values = line.map((index) => result[index]).toList();
      final collapsed = _collapse(values, (_) {});
      for (var index = 0; index < line.length; index++) {
        result[line[index]] = collapsed[index];
      }
    }
    return result;
  }

  static List<List<int>> _lines(int size, Direction2048 direction) {
    final lines = <List<int>>[];
    for (var i = 0; i < size; i++) {
      final line = <int>[];
      for (var j = 0; j < size; j++) {
        line.add(switch (direction) {
          Direction2048.left => i * size + j,
          Direction2048.right => i * size + (size - 1 - j),
          Direction2048.up => j * size + i,
          Direction2048.down => (size - 1 - j) * size + i,
        });
      }
      lines.add(line);
    }
    return lines;
  }

  static List<int> _collapse(List<int> values, void Function(int) onMerge) {
    final compact = values.where((value) => value != 0).toList();
    final merged = <int>[];
    var index = 0;
    while (index < compact.length) {
      if (index + 1 < compact.length && compact[index] == compact[index + 1]) {
        final value = compact[index] * 2;
        merged.add(value);
        onMerge(value);
        index += 2;
      } else {
        merged.add(compact[index]);
        index += 1;
      }
    }
    while (merged.length < values.length) {
      merged.add(0);
    }
    return merged;
  }

  void _spawn() {
    final empty = <int>[];
    for (var index = 0; index < cells.length; index++) {
      if (cells[index] == 0) empty.add(index);
    }
    if (empty.isEmpty) return;
    final index = empty[_random.nextInt(empty.length)];
    cells[index] = _random.nextInt(10) == 0 ? 4 : 2;
  }
}

class Game2048Bot {
  static Direction2048? chooseMove(
    List<int> cells, {
    int depth = 3,
    int maxChanceSamples = 4,
  }) {
    Direction2048? best;
    var bestScore = double.negativeInfinity;
    for (final direction in Direction2048.values) {
      final next = Game2048.slideBoard(cells, direction);
      if (listEquals(next, cells)) continue;
      final score = _chanceValue(next, depth, maxChanceSamples);
      if (score > bestScore) {
        bestScore = score;
        best = direction;
      }
    }
    return best;
  }

  static double _maxValue(List<int> cells, int depth, int maxChanceSamples) {
    if (depth <= 0) return _evaluate(cells);
    var best = double.negativeInfinity;
    for (final direction in Direction2048.values) {
      final next = Game2048.slideBoard(cells, direction);
      if (listEquals(next, cells)) continue;
      final score = _chanceValue(next, depth, maxChanceSamples);
      if (score > best) best = score;
    }
    return best == double.negativeInfinity ? _evaluate(cells) : best;
  }

  static double _chanceValue(List<int> cells, int depth, int maxChanceSamples) {
    final empties = <int>[];
    for (var index = 0; index < cells.length; index++) {
      if (cells[index] == 0) empties.add(index);
    }
    if (empties.isEmpty) return _maxValue(cells, depth - 1, maxChanceSamples);
    final sample = empties.length <= maxChanceSamples
        ? empties
        : empties.sublist(0, maxChanceSamples);
    var total = 0.0;
    for (final index in sample) {
      final withTwo = List<int>.of(cells)..[index] = 2;
      final withFour = List<int>.of(cells)..[index] = 4;
      total += 0.9 * _maxValue(withTwo, depth - 1, maxChanceSamples);
      total += 0.1 * _maxValue(withFour, depth - 1, maxChanceSamples);
    }
    return total / sample.length;
  }

  static double _evaluate(List<int> cells) {
    final size = sqrt(cells.length).round();
    var empties = 0;
    for (final value in cells) {
      if (value == 0) empties++;
    }
    return empties * 2.7 +
        _monotonicity(cells, size) +
        _smoothness(cells, size) * 0.1 +
        _maxTile(cells);
  }

  static double _maxTile(List<int> cells) {
    var maxValue = 0;
    for (final value in cells) {
      if (value > maxValue) maxValue = value;
    }
    return _log2(maxValue);
  }

  static double _smoothness(List<int> cells, int size) {
    var smoothness = 0.0;
    for (var row = 0; row < size; row++) {
      for (var column = 0; column < size; column++) {
        final index = row * size + column;
        if (cells[index] == 0) continue;
        final value = _log2(cells[index]);
        if (column + 1 < size && cells[index + 1] != 0) {
          smoothness -= (value - _log2(cells[index + 1])).abs();
        }
        if (row + 1 < size && cells[index + size] != 0) {
          smoothness -= (value - _log2(cells[index + size])).abs();
        }
      }
    }
    return smoothness;
  }

  static double _monotonicity(List<int> cells, int size) {
    final totals = <double>[0, 0, 0, 0];
    for (var row = 0; row < size; row++) {
      for (var column = 0; column + 1 < size; column++) {
        final current = _log2(cells[row * size + column]);
        final next = _log2(cells[row * size + column + 1]);
        if (current > next) {
          totals[0] += next - current;
        } else if (current < next) {
          totals[1] += current - next;
        }
      }
    }
    for (var column = 0; column < size; column++) {
      for (var row = 0; row + 1 < size; row++) {
        final current = _log2(cells[row * size + column]);
        final next = _log2(cells[(row + 1) * size + column]);
        if (current > next) {
          totals[2] += next - current;
        } else if (current < next) {
          totals[3] += current - next;
        }
      }
    }
    return max(totals[0], totals[1]) + max(totals[2], totals[3]);
  }

  static double _log2(int value) =>
      value <= 0 ? 0 : log(value.toDouble()) / ln2;
}

Color _tile2048Color(int value) => switch (value) {
  2 => const Color(0xffeee4da),
  4 => const Color(0xffede0c8),
  8 => const Color(0xfff2b179),
  16 => const Color(0xfff59563),
  32 => const Color(0xfff67c5f),
  64 => const Color(0xfff65e3b),
  128 => const Color(0xffedcf72),
  256 => const Color(0xffedcc61),
  512 => const Color(0xffedc850),
  1024 => const Color(0xffedc53f),
  2048 => const Color(0xffedc22e),
  _ => const Color(0xff3c3a32),
};

double _tile2048FontSize(int value, int boardSize) {
  final base = switch (boardSize) {
    3 => 40.0,
    4 => 30.0,
    5 => 24.0,
    _ => 19.0,
  };
  if (value < 100) return base;
  if (value < 1000) return base * 0.85;
  if (value < 10000) return base * 0.68;
  return base * 0.55;
}

class Game2048Screen extends StatefulWidget {
  const Game2048Screen({super.key});
  @override
  State<Game2048Screen> createState() => _Game2048ScreenState();
}

class _Game2048ScreenState extends State<Game2048Screen> {
  late Game2048 _game;
  Game2048Mode _mode = Game2048Mode.classic;
  final _preferences = LocalPreferences();
  final _focusNode = FocusNode();
  Offset _dragDelta = Offset.zero;
  int _best = 0;
  bool _wonShown = false;
  Timer? _autoTimer;

  bool get _autoPlaying => _autoTimer != null;

  String get _bestKey => 'game_2048_best_${_mode.size}';

  @override
  void initState() {
    super.initState();
    _startMode(_mode);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _startMode(Game2048Mode mode) {
    _mode = mode;
    _game = Game2048(size: mode.size, target: mode.target);
    _game.reset();
    _wonShown = false;
    _best = 0;
    _loadBest();
  }

  void _changeMode(Game2048Mode mode) {
    if (mode == _mode) return;
    _autoTimer?.cancel();
    _autoTimer = null;
    setState(() => _startMode(mode));
  }

  Future<void> _loadBest() async {
    final key = _bestKey;
    final stored = await _preferences.getString(key);
    final value = int.tryParse(stored ?? '');
    if (!mounted || value == null || key != _bestKey) return;
    setState(() => _best = value);
  }

  void _move(Direction2048 direction) {
    if (!_game.move(direction)) return;
    setState(() {
      if (_game.score > _best) {
        _best = _game.score;
        unawaited(_preferences.setString(_bestKey, '$_best'));
      }
    });
    if (!_wonShown &&
        !_autoPlaying &&
        _game.cells.any((value) => value >= _game.target)) {
      _wonShown = true;
      _showWin();
    }
  }

  void _toggleAuto() {
    if (_autoPlaying) {
      _stopAuto();
      return;
    }
    setState(() {
      _autoTimer = Timer.periodic(
        const Duration(milliseconds: 320),
        (_) => _autoStep(),
      );
    });
    _autoStep();
  }

  void _autoStep() {
    if (!_game.hasMoves) {
      _stopAuto();
      return;
    }
    final move = Game2048Bot.chooseMove(_game.cells);
    if (move == null) {
      _stopAuto();
      return;
    }
    _move(move);
    if (!_game.hasMoves) _stopAuto();
  }

  void _stopAuto() {
    _autoTimer?.cancel();
    _autoTimer = null;
    if (mounted) setState(() {});
  }

  Future<void> _showWin() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr(context, 'You win!', '你赢了！')),
      content: Text(
        tr(context, 'You reached ${_game.target}.', '你合成了 ${_game.target}。'),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(context, 'Keep going', '继续')),
        ),
      ],
    ),
  );

  void _restart() {
    setState(() {
      _game.reset();
      _wonShown = false;
    });
    _focusNode.requestFocus();
  }

  void _endDrag() {
    final delta = _dragDelta;
    _dragDelta = Offset.zero;
    if (delta.distance < 24) return;
    if (delta.dx.abs() > delta.dy.abs()) {
      _move(delta.dx > 0 ? Direction2048.right : Direction2048.left);
    } else {
      _move(delta.dy > 0 ? Direction2048.down : Direction2048.up);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.keyW => Direction2048.up,
      LogicalKeyboardKey.arrowDown ||
      LogicalKeyboardKey.keyS => Direction2048.down,
      LogicalKeyboardKey.arrowLeft ||
      LogicalKeyboardKey.keyA => Direction2048.left,
      LogicalKeyboardKey.arrowRight ||
      LogicalKeyboardKey.keyD => Direction2048.right,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;
    _move(direction);
    return KeyEventResult.handled;
  }

  Widget _scoreBox(BuildContext context, String label, int value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _board(BuildContext context, double side) {
    final size = _game.size;
    final spacing = size <= 4 ? 8.0 : 5.0;
    return SizedBox(
      width: side,
      height: side,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            for (var row = 0; row < size; row++) ...[
              if (row > 0) SizedBox(height: spacing),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < size; column++) ...[
                      if (column > 0) SizedBox(width: spacing),
                      Expanded(
                        child: _Tile2048(
                          key: ValueKey('tile-$row-$column'),
                          value: _game.cells[row * size + column],
                          boardSize: size,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _gameOver(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
    ),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tr(context, 'Game over', '游戏结束'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _restart,
          child: Text(tr(context, 'Try again', '再来一局')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, '2048', '2048')),
      actions: [
        PopupMenuButton<Game2048Mode>(
          tooltip: tr(context, 'Board size', '棋盘大小'),
          initialValue: _mode,
          onSelected: _changeMode,
          icon: const Icon(Icons.grid_on),
          itemBuilder: (context) => [
            for (final mode in Game2048Mode.values)
              PopupMenuItem(value: mode, child: Text(mode.label)),
          ],
        ),
        IconButton(
          tooltip: _autoPlaying
              ? tr(context, 'Pause auto play', '暂停自动游玩')
              : tr(context, 'Auto play', '自动游玩'),
          onPressed: _toggleAuto,
          icon: Icon(
            _autoPlaying
                ? Icons.pause_circle_outline
                : Icons.play_circle_outline,
          ),
        ),
        IconButton(
          tooltip: tr(context, 'Restart', '重新开始'),
          onPressed: _restart,
          icon: const Icon(Icons.restart_alt),
        ),
        toolInfoAction(context, '2048'),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _onKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = min(
                  constraints.maxWidth,
                  (constraints.maxHeight - 128).clamp(160.0, 480.0),
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _mode.label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Row(
                          children: [
                            _scoreBox(
                              context,
                              tr(context, 'Score', '得分'),
                              _game.score,
                            ),
                            const SizedBox(width: 8),
                            _scoreBox(
                              context,
                              tr(context, 'Best', '最高'),
                              _best,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _focusNode.requestFocus(),
                      onPanStart: (_) => _dragDelta = Offset.zero,
                      onPanUpdate: (details) => _dragDelta += details.delta,
                      onPanEnd: (_) => _endDrag(),
                      child: Stack(
                        children: [
                          _board(context, side),
                          if (!_game.hasMoves)
                            Positioned.fill(child: _gameOver(context)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      tr(
                        context,
                        'Use arrow keys, WASD or swipe to move.',
                        '使用方向键、WASD 或滑动来移动。',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class _Tile2048 extends StatelessWidget {
  const _Tile2048({super.key, required this.value, required this.boardSize});
  final int value;
  final int boardSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (value == 0) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: _tile2048Color(value),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        '$value',
        style: TextStyle(
          color: value <= 4 ? const Color(0xff776e65) : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: _tile2048FontSize(value, boardSize),
        ),
      ),
    );
  }
}

enum TicTacToePlayer { x, o }

enum TicTacToeDifficulty {
  easy('Easy', '简单'),
  normal('Normal', '普通'),
  hard('Hard', '困难');

  const TicTacToeDifficulty(this.english, this.chinese);
  final String english;
  final String chinese;
}

enum TicTacToeMode {
  vsBot('Vs bot', '人机对战'),
  twoPlayers('Two players', '双人模式');

  const TicTacToeMode(this.english, this.chinese);
  final String english;
  final String chinese;
}

class TicTacToe {
  TicTacToe({List<TicTacToePlayer?>? cells})
    : cells = cells == null
          ? List<TicTacToePlayer?>.filled(9, null)
          : List<TicTacToePlayer?>.of(cells);

  static const lines = <List<int>>[
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ];

  final List<TicTacToePlayer?> cells;

  void reset() => cells.fillRange(0, cells.length, null);

  List<int> get emptyCells {
    final result = <int>[];
    for (var index = 0; index < cells.length; index++) {
      if (cells[index] == null) result.add(index);
    }
    return result;
  }

  bool get isFull => emptyCells.isEmpty;

  TicTacToePlayer? get winner {
    for (final line in lines) {
      final first = cells[line[0]];
      if (first != null && cells[line[1]] == first && cells[line[2]] == first) {
        return first;
      }
    }
    return null;
  }

  bool get isDraw => winner == null && isFull;

  bool get isOver => winner != null || isFull;

  bool get isDeadDraw {
    for (final line in lines) {
      var hasX = false;
      var hasO = false;
      for (final index in line) {
        if (cells[index] == TicTacToePlayer.x) {
          hasX = true;
        } else if (cells[index] == TicTacToePlayer.o) {
          hasO = true;
        }
      }
      if (!hasX || !hasO) return false;
    }
    return true;
  }

  TicTacToePlayer get currentPlayer {
    var x = 0;
    var o = 0;
    for (final cell in cells) {
      if (cell == TicTacToePlayer.x) {
        x++;
      } else if (cell == TicTacToePlayer.o) {
        o++;
      }
    }
    return x <= o ? TicTacToePlayer.x : TicTacToePlayer.o;
  }

  bool play(int index, TicTacToePlayer player) {
    if (index < 0 || index >= cells.length || cells[index] != null) {
      return false;
    }
    cells[index] = player;
    return true;
  }
}

class TicTacToeBot {
  static int? chooseMove(
    List<TicTacToePlayer?> cells, {
    required TicTacToePlayer self,
    required TicTacToePlayer opponent,
    TicTacToeDifficulty difficulty = TicTacToeDifficulty.normal,
    Random? random,
  }) {
    final game = TicTacToe(cells: cells);
    final empties = game.emptyCells;
    if (empties.isEmpty) return null;
    final rng = random ?? Random();
    if (difficulty == TicTacToeDifficulty.easy) {
      return empties[rng.nextInt(empties.length)];
    }
    if (difficulty == TicTacToeDifficulty.normal) {
      final winning = _findWinningMove(game, self);
      if (winning != null) return winning;
      final blocking = _findWinningMove(game, opponent);
      if (blocking != null) return blocking;
      if (game.cells[4] == null) return 4;
      final corners = [
        0,
        2,
        6,
        8,
      ].where((index) => game.cells[index] == null).toList();
      if (corners.isNotEmpty) return corners[rng.nextInt(corners.length)];
      return empties[rng.nextInt(empties.length)];
    }
    var bestScore = -1000;
    int? best;
    for (final index in empties) {
      game.cells[index] = self;
      final score = _minimax(game, self, opponent, false, 0);
      game.cells[index] = null;
      if (score > bestScore) {
        bestScore = score;
        best = index;
      }
    }
    return best;
  }

  static TicTacToePlayer? forcedWinner(List<TicTacToePlayer?> cells) {
    final game = TicTacToe(cells: cells);
    if (game.isOver) return game.winner;
    final score = _minimax(
      game,
      TicTacToePlayer.x,
      TicTacToePlayer.o,
      game.currentPlayer == TicTacToePlayer.x,
      0,
    );
    if (score > 0) return TicTacToePlayer.x;
    if (score < 0) return TicTacToePlayer.o;
    return null;
  }

  static int? _findWinningMove(TicTacToe game, TicTacToePlayer player) {
    for (final index in game.emptyCells) {
      game.cells[index] = player;
      final wins = game.winner == player;
      game.cells[index] = null;
      if (wins) return index;
    }
    return null;
  }

  static int _minimax(
    TicTacToe game,
    TicTacToePlayer self,
    TicTacToePlayer opponent,
    bool maximizing,
    int depth,
  ) {
    final winner = game.winner;
    if (winner == self) return 10 - depth;
    if (winner == opponent) return depth - 10;
    if (game.isFull) return 0;
    final empties = game.emptyCells;
    if (maximizing) {
      var best = -1000;
      for (final index in empties) {
        game.cells[index] = self;
        best = max(best, _minimax(game, self, opponent, false, depth + 1));
        game.cells[index] = null;
      }
      return best;
    }
    var best = 1000;
    for (final index in empties) {
      game.cells[index] = opponent;
      best = min(best, _minimax(game, self, opponent, true, depth + 1));
      game.cells[index] = null;
    }
    return best;
  }
}

class TicTacToeScreen extends StatefulWidget {
  const TicTacToeScreen({super.key});
  @override
  State<TicTacToeScreen> createState() => _TicTacToeScreenState();
}

class _TicTacToeScreenState extends State<TicTacToeScreen> {
  static const _defaultX = 'X';
  static const _defaultO = 'O';
  static const _symbolXKey = 'tic_tac_toe_symbol_x';
  static const _symbolOKey = 'tic_tac_toe_symbol_o';

  final _game = TicTacToe();
  final _preferences = LocalPreferences();
  TicTacToeMode _mode = TicTacToeMode.vsBot;
  TicTacToeDifficulty _difficulty = TicTacToeDifficulty.normal;
  String _xSymbol = _defaultX;
  String _oSymbol = _defaultO;
  Timer? _botTimer;
  bool _thinking = false;
  bool _resultCounted = false;
  bool _quickEnd = false;
  TicTacToePlayer? _earlyWinner;
  bool _earlyDraw = false;
  int _wins = 0;
  int _losses = 0;
  int _draws = 0;

  bool get _isGameOver => _game.isOver || _earlyWinner != null || _earlyDraw;

  TicTacToePlayer? get _resultWinner => _game.winner ?? _earlyWinner;

  @override
  void initState() {
    super.initState();
    _loadSymbols();
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSymbols() async {
    final x = await _preferences.getString(_symbolXKey);
    final o = await _preferences.getString(_symbolOKey);
    if (!mounted) return;
    setState(() {
      if (x != null && x.trim().isNotEmpty) _xSymbol = x;
      if (o != null && o.trim().isNotEmpty) _oSymbol = o;
    });
  }

  void _onCellTap(int index) {
    if (_thinking || _isGameOver || _game.cells[index] != null) return;
    final player = _game.currentPlayer;
    if (_mode == TicTacToeMode.vsBot && player != TicTacToePlayer.x) return;
    setState(() {
      _game.play(index, player);
      _detectEarlyResult();
      _finishIfOver();
    });
    if (_isGameOver) return;
    if (_mode == TicTacToeMode.vsBot) _scheduleBot();
  }

  void _changeMode(TicTacToeMode mode) {
    if (mode == _mode) return;
    _botTimer?.cancel();
    setState(() {
      _mode = mode;
      _game.reset();
      _thinking = false;
      _resultCounted = false;
      _earlyWinner = null;
      _earlyDraw = false;
    });
  }

  void _scheduleBot() {
    _botTimer?.cancel();
    setState(() => _thinking = true);
    _botTimer = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final move = TicTacToeBot.chooseMove(
        _game.cells,
        self: TicTacToePlayer.o,
        opponent: TicTacToePlayer.x,
        difficulty: _difficulty,
      );
      setState(() {
        _thinking = false;
        if (move != null) _game.play(move, TicTacToePlayer.o);
        _detectEarlyResult();
        _finishIfOver();
      });
    });
  }

  void _detectEarlyResult() {
    if (!_quickEnd || _isGameOver || _game.isOver) return;
    final forced = TicTacToeBot.forcedWinner(_game.cells);
    if (forced != null) {
      _earlyWinner = forced;
    } else if (_game.isDeadDraw) {
      _earlyDraw = true;
    }
  }

  void _toggleQuickEnd() {
    setState(() {
      _quickEnd = !_quickEnd;
      _detectEarlyResult();
      _finishIfOver();
    });
  }

  void _finishIfOver() {
    if (!_isGameOver || _resultCounted) return;
    _resultCounted = true;
    final winner = _resultWinner;
    if (winner == TicTacToePlayer.x) {
      _wins++;
    } else if (winner == TicTacToePlayer.o) {
      _losses++;
    } else {
      _draws++;
    }
  }

  void _restart() {
    _botTimer?.cancel();
    setState(() {
      _game.reset();
      _thinking = false;
      _resultCounted = false;
      _earlyWinner = null;
      _earlyDraw = false;
    });
  }

  Future<void> _editSymbols() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _SymbolDialog(x: _xSymbol, o: _oSymbol),
    );
    if (result == null || !mounted) return;
    final x = result.$1.trim().isEmpty ? _defaultX : result.$1.trim();
    final o = result.$2.trim().isEmpty ? _defaultO : result.$2.trim();
    if (x == o) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(context, 'Choose two different symbols.', '请选择两个不同的符号。'),
          ),
        ),
      );
      return;
    }
    setState(() {
      _xSymbol = x;
      _oSymbol = o;
    });
    await _preferences.setString(_symbolXKey, x);
    await _preferences.setString(_symbolOKey, o);
  }

  String _symbolFor(TicTacToePlayer? player) => switch (player) {
    TicTacToePlayer.x => _xSymbol,
    TicTacToePlayer.o => _oSymbol,
    null => '',
  };

  Color _colorFor(BuildContext context, TicTacToePlayer? player) =>
      switch (player) {
        TicTacToePlayer.x => Theme.of(context).colorScheme.primary,
        TicTacToePlayer.o => Theme.of(context).colorScheme.tertiary,
        null => Colors.transparent,
      };

  String _status(BuildContext context) {
    final winner = _resultWinner;
    if (winner != null) {
      if (_mode == TicTacToeMode.twoPlayers) {
        final symbol = _symbolFor(winner);
        return tr(context, '$symbol wins!', '$symbol 获胜！');
      }
      return winner == TicTacToePlayer.x
          ? tr(context, 'You win!', '你赢了！')
          : tr(context, 'You lose', '你输了');
    }
    if (_earlyDraw || _game.isFull) return tr(context, 'Draw', '平局');
    if (_thinking) return tr(context, 'Bot is thinking…', '电脑思考中…');
    if (_mode == TicTacToeMode.twoPlayers) {
      final symbol = _symbolFor(_game.currentPlayer);
      return tr(context, "$symbol's turn", '轮到 $symbol');
    }
    return tr(context, 'Your turn', '轮到你');
  }

  Widget _stat(BuildContext context, String label, int value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _board(BuildContext context, double side) => SizedBox(
    width: side,
    height: side,
    child: Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var row = 0; row < 3; row++) ...[
            if (row > 0) const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < 3; column++) ...[
                    if (column > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _TicTacToeCell(
                        key: ValueKey('tic-tac-toe-${row * 3 + column}'),
                        symbol: _symbolFor(_game.cells[row * 3 + column]),
                        color: _colorFor(
                          context,
                          _game.cells[row * 3 + column],
                        ),
                        onTap: () => _onCellTap(row * 3 + column),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'Tic-Tac-Toe', '井字棋')),
      actions: [
        PopupMenuButton<TicTacToeMode>(
          tooltip: tr(context, 'Game mode', '游戏模式'),
          initialValue: _mode,
          onSelected: _changeMode,
          icon: Icon(
            _mode == TicTacToeMode.vsBot
                ? Icons.smart_toy_outlined
                : Icons.group_outlined,
          ),
          itemBuilder: (context) => [
            for (final mode in TicTacToeMode.values)
              PopupMenuItem(
                value: mode,
                child: Text(tr(context, mode.english, mode.chinese)),
              ),
          ],
        ),
        if (_mode == TicTacToeMode.vsBot)
          PopupMenuButton<TicTacToeDifficulty>(
            tooltip: tr(context, 'Difficulty', '难度'),
            initialValue: _difficulty,
            onSelected: (value) => setState(() => _difficulty = value),
            icon: const Icon(Icons.speed),
            itemBuilder: (context) => [
              for (final level in TicTacToeDifficulty.values)
                PopupMenuItem(
                  value: level,
                  child: Text(tr(context, level.english, level.chinese)),
                ),
            ],
          ),
        IconButton(
          tooltip: _quickEnd
              ? tr(context, 'Quick result detection: on', '快速判定胜负：开')
              : tr(context, 'Quick result detection: off', '快速判定胜负：关'),
          onPressed: _toggleQuickEnd,
          isSelected: _quickEnd,
          icon: const Icon(Icons.flash_off),
          selectedIcon: const Icon(Icons.flash_on),
          style: IconButton.styleFrom(
            backgroundColor: _quickEnd
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            foregroundColor: _quickEnd
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : null,
          ),
        ),
        IconButton(
          tooltip: tr(context, 'Customize symbols', '自定义符号'),
          onPressed: _editSymbols,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: tr(context, 'Restart', '重新开始'),
          onPressed: _restart,
          icon: const Icon(Icons.restart_alt),
        ),
        toolInfoAction(context, 'tic-tac-toe'),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = min(
                constraints.maxWidth,
                (constraints.maxHeight - 200).clamp(180.0, 360.0),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _stat(
                        context,
                        _mode == TicTacToeMode.vsBot
                            ? tr(context, 'Wins', '胜')
                            : _xSymbol,
                        _wins,
                      ),
                      _stat(context, tr(context, 'Draws', '平'), _draws),
                      _stat(
                        context,
                        _mode == TicTacToeMode.vsBot
                            ? tr(context, 'Losses', '负')
                            : _oSymbol,
                        _losses,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _board(context, side),
                  const SizedBox(height: 16),
                  Text(
                    _status(context),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Opacity(
                    opacity: _isGameOver ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !_isGameOver,
                      child: FilledButton(
                        onPressed: _restart,
                        child: Text(tr(context, 'New game', '新的一局')),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _TicTacToeCell extends StatelessWidget {
  const _TicTacToeCell({
    super.key,
    required this.symbol,
    required this.color,
    required this.onTap,
  });

  final String symbol;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: symbol.isEmpty
            ? const SizedBox.expand()
            : FittedBox(
                child: Text(
                  symbol,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
      ),
    ),
  );
}

class _SymbolDialog extends StatefulWidget {
  const _SymbolDialog({required this.x, required this.o});

  final String x;
  final String o;

  @override
  State<_SymbolDialog> createState() => _SymbolDialogState();
}

class _SymbolDialogState extends State<_SymbolDialog> {
  late final TextEditingController _xController = TextEditingController(
    text: widget.x,
  );
  late final TextEditingController _oController = TextEditingController(
    text: widget.o,
  );

  @override
  void dispose() {
    _xController.dispose();
    _oController.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.pop(context, (_xController.text, _oController.text));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr(context, 'Customize symbols', '自定义符号')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _xController,
          autofocus: true,
          maxLength: 2,
          decoration: InputDecoration(
            labelText: tr(context, 'Your symbol', '你的符号'),
          ),
        ),
        TextField(
          controller: _oController,
          maxLength: 2,
          decoration: InputDecoration(
            labelText: tr(context, 'Bot symbol', '电脑符号'),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(tr(context, 'Cancel', '取消')),
      ),
      FilledButton(onPressed: _submit, child: Text(tr(context, 'Save', '保存'))),
    ],
  );
}

class _FlashlightChannel {
  static const _channel = MethodChannel('pockito/flashlight');

  static Future<bool> isAvailable() async =>
      await _channel.invokeMethod<bool>('isAvailable') ?? false;

  static Future<int> maxStrength() async =>
      await _channel.invokeMethod<int>('getMaxStrength') ?? 0;

  static Future<bool> isTorchOn() async =>
      await _channel.invokeMethod<bool>('isTorchOn') ?? false;

  static Future<void> setTorch({required bool on, int? strength}) {
    final arguments = <String, Object?>{'on': on};
    if (strength != null) arguments['strength'] = strength;
    return _channel.invokeMethod<void>('setTorch', arguments);
  }
}

const Map<String, String> morseAlphabet = {
  'A': '.-',
  'B': '-...',
  'C': '-.-.',
  'D': '-..',
  'E': '.',
  'F': '..-.',
  'G': '--.',
  'H': '....',
  'I': '..',
  'J': '.---',
  'K': '-.-',
  'L': '.-..',
  'M': '--',
  'N': '-.',
  'O': '---',
  'P': '.--.',
  'Q': '--.-',
  'R': '.-.',
  'S': '...',
  'T': '-',
  'U': '..-',
  'V': '...-',
  'W': '.--',
  'X': '-..-',
  'Y': '-.--',
  'Z': '--..',
  '0': '-----',
  '1': '.----',
  '2': '..---',
  '3': '...--',
  '4': '....-',
  '5': '.....',
  '6': '-....',
  '7': '--...',
  '8': '---..',
  '9': '----.',
};

bool _isCjkRune(int rune) =>
    (rune >= 0x4e00 && rune <= 0x9fff) || (rune >= 0x3400 && rune <= 0x4dbf);

String _latinizeForMorse(String word) {
  final buffer = StringBuffer();
  for (final rune in word.runes) {
    if (_isCjkRune(rune)) {
      buffer.write(
        PinyinHelper.getPinyinE(
          String.fromCharCode(rune),
          separator: '',
          format: PinyinFormat.WITHOUT_TONE,
        ),
      );
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

String textToMorse(String text) {
  final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return '';
  final encodedWords = <String>[];
  for (final rawWord in normalized.split(' ')) {
    final latin = _latinizeForMorse(rawWord).toUpperCase();
    final letters = <String>[];
    for (final rune in latin.runes) {
      final code = morseAlphabet[String.fromCharCode(rune)];
      if (code != null) letters.add(code);
    }
    if (letters.isNotEmpty) encodedWords.add(letters.join(' '));
  }
  return encodedWords.join(' / ');
}

List<int> morseBlinkPattern(String morse, {int unit = 200}) {
  final pattern = <int>[];
  final words = morse.trim().split('/');
  var hasContent = false;
  for (final rawWord in words) {
    final letters = rawWord
        .trim()
        .split(RegExp(r'\s+'))
        .where((letter) => letter.isNotEmpty)
        .toList();
    if (letters.isEmpty) continue;
    if (hasContent) pattern.add(7 * unit);
    for (var letter = 0; letter < letters.length; letter++) {
      if (letter > 0) pattern.add(3 * unit);
      final symbols = letters[letter].split('');
      for (var symbol = 0; symbol < symbols.length; symbol++) {
        if (symbol > 0) pattern.add(1 * unit);
        pattern.add((symbols[symbol] == '-' ? 3 : 1) * unit);
      }
    }
    hasContent = true;
  }
  return pattern;
}

class _TorchBlinkPlayer {
  _TorchBlinkPlayer(this._apply);

  final Future<void> Function(bool on) _apply;
  Timer? _timer;
  List<int> _pattern = const [];
  bool _repeat = false;
  int _index = 0;
  VoidCallback? onDone;

  bool get isRunning => _timer != null;

  void start(List<int> pattern, {bool repeat = false}) {
    stop();
    if (pattern.isEmpty) return;
    _pattern = pattern;
    _repeat = repeat;
    _index = 0;
    _schedule();
  }

  void _schedule() {
    if (_index >= _pattern.length) {
      if (!_repeat) {
        _timer = null;
        unawaited(_apply(false));
        onDone?.call();
        return;
      }
      _index = 0;
    }
    final on = _index.isEven;
    final delay = _pattern[_index];
    _index++;
    unawaited(_apply(on));
    _timer = Timer(Duration(milliseconds: delay), _schedule);
  }

  void stop({bool apply = true}) {
    _timer?.cancel();
    _timer = null;
    _index = 0;
    if (apply) unawaited(_apply(false));
  }

  void dispose() => stop(apply: false);
}

enum _FlashMode { off, steady, sos, periodic, morse }

class FlashlightScreen extends StatefulWidget {
  const FlashlightScreen({super.key});
  @override
  State<FlashlightScreen> createState() => _FlashlightScreenState();
}

class _FlashlightScreenState extends State<FlashlightScreen>
    with WidgetsBindingObserver {
  static const _torchTimeout = Duration(seconds: 2);
  final _morseController = TextEditingController();
  late final _player = _TorchBlinkPlayer(_applyTorch);
  bool? _supported;
  int _maxStrength = 1;
  int _strength = 1;
  int _periodMs = 500;
  String _morseOutput = '';
  String? _lastError;
  _FlashMode _mode = _FlashMode.off;

  bool get _supportsStrength => _maxStrength > 1;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.onDone = () {
      if (mounted) setState(() => _mode = _FlashMode.off);
    };
    _checkSupport();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    unawaited(_FlashlightChannel.setTorch(on: false).catchError((_) {}));
    _morseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _syncWithHardware();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stopBlinkForBackground();
    }
  }

  Future<void> _syncWithHardware() async {
    if (_supported != true) return;
    bool actualOn;
    try {
      actualOn = await _FlashlightChannel.isTorchOn().timeout(_torchTimeout);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      if (_mode == _FlashMode.steady) {
        if (!actualOn) _mode = _FlashMode.off;
      } else if (_mode == _FlashMode.off && actualOn) {
        _mode = _FlashMode.steady;
      }
    });
  }

  void _stopBlinkForBackground() {
    // Blink patterns rely on Dart timers, which the OS suspends while the app
    // is in the background, so stop them and leave the torch off.
    if (_mode == _FlashMode.sos ||
        _mode == _FlashMode.periodic ||
        _mode == _FlashMode.morse) {
      _player.stop();
      setState(() => _mode = _FlashMode.off);
    }
  }

  Future<void> _checkSupport() async {
    var supported = false;
    var maxStrength = 0;
    try {
      supported = await _FlashlightChannel.isAvailable().timeout(_torchTimeout);
      if (supported) {
        maxStrength = await _FlashlightChannel.maxStrength().timeout(
          _torchTimeout,
        );
      }
    } catch (_) {
      supported = false;
    }
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _maxStrength = maxStrength;
      _strength = maxStrength < 1 ? 1 : maxStrength;
    });
  }

  Future<void> _applyTorch(bool on) async {
    await _applyTorchInternal(on);
  }

  Future<String?> _applyTorchInternal(bool on) async {
    try {
      await _FlashlightChannel.setTorch(
        on: on,
        strength: on && _supportsStrength ? _strength : null,
      ).timeout(_torchTimeout);
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  void _runTorchAction(bool on) {
    unawaited(
      _applyTorchInternal(on).then((error) {
        if (!mounted) return;
        setState(() => _lastError = error);
      }),
    );
  }

  void _setMode(_FlashMode mode) {
    _player.stop();
    if (mode == _FlashMode.off) {
      setState(() => _mode = _FlashMode.off);
    } else if (mode == _FlashMode.steady) {
      setState(() => _mode = _FlashMode.steady);
      _runTorchAction(true);
    } else if (mode == _FlashMode.sos) {
      setState(() => _mode = _FlashMode.sos);
      _player.start(morseBlinkPattern(textToMorse('SOS')), repeat: true);
    } else if (mode == _FlashMode.periodic) {
      setState(() => _mode = _FlashMode.periodic);
      _player.start([_periodMs, _periodMs], repeat: true);
    } else {
      final pattern = morseBlinkPattern(_morseOutput);
      if (pattern.isEmpty) {
        setState(() => _mode = _FlashMode.off);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(context, 'Nothing to send yet.', '还没有可发送的内容。')),
          ),
        );
      } else {
        setState(() => _mode = _FlashMode.morse);
        _player.start(pattern);
      }
    }
  }

  void _changeStrength(double value) {
    setState(() => _strength = value.round());
    if (_mode == _FlashMode.steady) _runTorchAction(true);
  }

  void _changePeriod(double value) {
    setState(() => _periodMs = value.round());
    if (_mode == _FlashMode.periodic) {
      _player.start([_periodMs, _periodMs], repeat: true);
    }
  }

  Widget _supportCard(BuildContext context) {
    final theme = Theme.of(context);
    final supported = _supported == true;
    return Card(
      color: supported
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  supported
                      ? Icons.flashlight_on_outlined
                      : Icons.flashlight_off_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    supported
                        ? tr(
                            context,
                            'Flashlight detected on this device.',
                            '已检测到本机手电筒。',
                          )
                        : tr(
                            context,
                            'No flashlight detected on this device. Torch controls are unavailable; you can still convert text to Morse code below.',
                            '未检测到本机手电筒。无法控制闪光灯，但仍可在下方把文字转换为摩尔斯电码。',
                          ),
                  ),
                ),
              ],
            ),
            if (supported) ...[
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  'Platform: ${Platform.operatingSystem} • torch brightness levels: $_maxStrength',
                  '平台：${Platform.operatingSystem} • 手电筒亮度级别：$_maxStrength',
                ),
                style: theme.textTheme.bodySmall,
              ),
              if (_lastError != null) ...[
                const SizedBox(height: 6),
                Text(
                  tr(context, 'Last error: $_lastError', '最近错误：$_lastError'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _modeButton({
    required String label,
    required IconData icon,
    required _FlashMode mode,
    bool enabled = true,
  }) {
    final active = _mode == mode;
    final onPressed = enabled
        ? () => _setMode(active ? _FlashMode.off : mode)
        : null;
    final child = Icon(icon);
    final text = Text(label);
    if (active) {
      return FilledButton.icon(onPressed: onPressed, icon: child, label: text);
    }
    return OutlinedButton.icon(onPressed: onPressed, icon: child, label: text);
  }

  Widget _steadySection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Flashlight', '手电筒'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _modeButton(
                  label: tr(context, 'On', '常亮'),
                  icon: Icons.lightbulb_outline,
                  mode: _FlashMode.steady,
                ),
                const SizedBox(width: 12),
                _modeButton(
                  label: tr(context, 'Off', '关闭'),
                  icon: Icons.lightbulb,
                  mode: _FlashMode.off,
                ),
              ],
            ),
            if (_supportsStrength) ...[
              const SizedBox(height: 12),
              Text(
                tr(
                  context,
                  'Brightness $_strength / $_maxStrength',
                  '亮度 $_strength / $_maxStrength',
                ),
              ),
              Slider(
                value: _strength.toDouble(),
                min: 1,
                max: _maxStrength.toDouble(),
                divisions: _maxStrength - 1,
                label: '$_strength',
                onChanged: _changeStrength,
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                _maxStrength == 1
                    ? tr(
                        context,
                        'This device reports a single brightness level, so the torch can only be on or off.',
                        '本机仅报告单一亮度级别，手电筒只能开或关。',
                      )
                    : tr(
                        context,
                        'Brightness control requires Android 13+.',
                        '亮度控制需要 Android 13+。',
                      ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _signalsSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Signals', '信号'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _modeButton(
                  label: tr(context, 'SOS', 'SOS'),
                  icon: Icons.sos_outlined,
                  mode: _FlashMode.sos,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              tr(
                context,
                'Fixed-period flashing: $_periodMs ms',
                '固定周期闪烁：$_periodMs 毫秒',
              ),
            ),
            Slider(
              value: _periodMs.toDouble(),
              min: 100,
              max: 2000,
              divisions: 19,
              label: '$_periodMs',
              onChanged: _changePeriod,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _modeButton(
                label: tr(context, 'Blink', '闪烁'),
                icon: Icons.flash_on_outlined,
                mode: _FlashMode.periodic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _morseSection(BuildContext context) {
    final canSend = _supported == true && _morseOutput.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Morse code', '摩尔斯电码'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _morseController,
              onChanged: (value) =>
                  setState(() => _morseOutput = textToMorse(value)),
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  'Text (letters, numbers or Chinese)',
                  '文字（字母、数字或中文）',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              _morseOutput.isEmpty
                  ? tr(context, 'Morse code appears here.', '摩尔斯电码将显示在这里。')
                  : _morseOutput,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _modeButton(
                  label: tr(context, 'Send', '发送'),
                  icon: Icons.send_outlined,
                  mode: _FlashMode.morse,
                  enabled: canSend,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _mode == _FlashMode.off
                      ? null
                      : () => _setMode(_FlashMode.off),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(tr(context, 'Stop', '停止')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'Flashlight', '手电筒')),
      actions: [
        if (_supported == true)
          IconButton(
            tooltip: tr(context, 'Stop', '停止'),
            onPressed: _mode == _FlashMode.off
                ? null
                : () => _setMode(_FlashMode.off),
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        toolInfoAction(context, 'flashlight'),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _supported == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                children: [
                  _supportCard(context),
                  const SizedBox(height: 16),
                  if (_supported == true) ...[
                    _steadySection(context),
                    const SizedBox(height: 16),
                    _signalsSection(context),
                    const SizedBox(height: 16),
                  ],
                  _morseSection(context),
                ],
              ),
      ),
    ),
  );
}

class VibrationPreset {
  const VibrationPreset({
    required this.id,
    required this.englishName,
    required this.chineseName,
    required this.pattern,
  });

  final String id;
  final String englishName;
  final String chineseName;
  final List<int> pattern;
}

const vibrationPresets = <VibrationPreset>[
  VibrationPreset(
    id: 'tap',
    englishName: 'Tap',
    chineseName: '轻点',
    pattern: [80],
  ),
  VibrationPreset(
    id: 'double',
    englishName: 'Double',
    chineseName: '双击',
    pattern: [80, 80, 80],
  ),
  VibrationPreset(
    id: 'triple',
    englishName: 'Triple',
    chineseName: '三连击',
    pattern: [80, 80, 80, 80, 80],
  ),
  VibrationPreset(
    id: 'long',
    englishName: 'Long',
    chineseName: '长震',
    pattern: [600],
  ),
  VibrationPreset(
    id: 'heartbeat',
    englishName: 'Heartbeat',
    chineseName: '心跳',
    pattern: [120, 100, 120, 500],
  ),
  VibrationPreset(
    id: 'sos',
    englishName: 'SOS',
    chineseName: 'SOS',
    pattern: [
      120,
      120,
      120,
      120,
      120,
      360,
      360,
      120,
      360,
      120,
      360,
      360,
      120,
      120,
      120,
      120,
      120,
      720,
    ],
  ),
  VibrationPreset(
    id: 'ripple',
    englishName: 'Ripple',
    chineseName: '涟漪',
    pattern: [60, 80, 120, 80, 180, 80, 240, 80, 180, 80, 120, 80, 60],
  ),
  VibrationPreset(
    id: 'tick',
    englishName: 'Tick tock',
    chineseName: '滴答',
    pattern: [50, 450, 80, 450],
  ),
  VibrationPreset(
    id: 'alarm',
    englishName: 'Alarm',
    chineseName: '警报',
    pattern: [400, 150, 400, 150, 400, 150, 400, 600],
  ),
];

List<int>? parseVibrationPattern(String input) {
  final parts = input
      .split(RegExp(r'[,\s]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty || parts.length > 64) return null;
  final values = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value <= 0 || value > 60000) return null;
    values.add(value);
  }
  return values;
}

int vibrationPatternDuration(List<int> pattern) =>
    pattern.fold(0, (total, segment) => total + segment);

String formatVibrationPattern(List<int> pattern) => pattern.join(', ');

enum VibrationStyle { soft, standard, crisp }

double vibrationSharpness(VibrationStyle style) => switch (style) {
  VibrationStyle.soft => 0.1,
  VibrationStyle.standard => 0.5,
  VibrationStyle.crisp => 1.0,
};

List<int> applyVibrationStyle(List<int> pattern, VibrationStyle style) {
  if (style != VibrationStyle.crisp) return pattern;
  const click = 20;
  return [
    for (var index = 0; index < pattern.length; index++)
      index.isEven ? min(pattern[index], click) : pattern[index],
  ];
}

class _VibratorChannel {
  static const _channel = MethodChannel('pockito/vibrator');

  static Future<bool> isAvailable() async =>
      await _channel.invokeMethod<bool>('isAvailable') ?? false;

  static Future<bool> hasAmplitudeControl() async =>
      await _channel.invokeMethod<bool>('hasAmplitudeControl') ?? false;

  static Future<void> vibrate({
    required List<int> pattern,
    int repeat = -1,
    int amplitude = -1,
    double sharpness = 0.5,
  }) => _channel.invokeMethod<void>('vibrate', {
    'pattern': pattern,
    'repeat': repeat,
    'amplitude': amplitude,
    'sharpness': sharpness,
  });

  static Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}

class VibratorScreen extends StatefulWidget {
  const VibratorScreen({super.key});
  @override
  State<VibratorScreen> createState() => _VibratorScreenState();
}

class _VibratorScreenState extends State<VibratorScreen>
    with WidgetsBindingObserver {
  static const _timeout = Duration(seconds: 2);
  final _customController = TextEditingController();
  bool? _supported;
  bool _hasAmplitude = false;
  int _amplitude = 255;
  bool _loop = false;
  VibrationStyle _style = VibrationStyle.standard;
  bool _playing = false;
  String? _activeId;
  String? _lastError;
  List<int>? _customPattern;
  String? _customError;
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSupport();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finishTimer?.cancel();
    unawaited(_VibratorChannel.cancel().catchError((_) {}));
    _customController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stop();
    }
  }

  Future<void> _checkSupport() async {
    var supported = false;
    var amplitude = false;
    try {
      supported = await _VibratorChannel.isAvailable().timeout(_timeout);
      if (supported) {
        amplitude = await _VibratorChannel.hasAmplitudeControl().timeout(
          _timeout,
        );
      }
    } catch (_) {
      supported = false;
    }
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _hasAmplitude = amplitude;
    });
  }

  void _play(List<int> pattern, String id) {
    if (pattern.isEmpty) return;
    final played = applyVibrationStyle(pattern, _style);
    _finishTimer?.cancel();
    setState(() {
      _playing = true;
      _activeId = id;
      _lastError = null;
    });
    unawaited(
      _VibratorChannel.vibrate(
            pattern: played,
            repeat: _loop ? 0 : -1,
            amplitude: _hasAmplitude ? _amplitude : -1,
            sharpness: vibrationSharpness(_style),
          )
          .then((_) {
            if (!mounted || _loop) return;
          })
          .catchError((Object error) {
            if (!mounted) return;
            setState(() {
              _playing = false;
              _activeId = null;
              _lastError = error.toString();
            });
          }),
    );
    if (!_loop) {
      _finishTimer = Timer(
        Duration(milliseconds: vibrationPatternDuration(played) + 50),
        () {
          if (!mounted) return;
          setState(() {
            _playing = false;
            _activeId = null;
          });
        },
      );
    }
  }

  void _playPreset(VibrationPreset preset) =>
      _play(preset.pattern, 'preset:${preset.id}');

  void _playCustom() {
    final pattern = _customPattern;
    if (pattern == null || pattern.isEmpty) return;
    _play(pattern, 'custom');
  }

  void _stop() {
    _finishTimer?.cancel();
    _finishTimer = null;
    unawaited(_VibratorChannel.cancel().catchError((_) {}));
    if (!mounted) return;
    setState(() {
      _playing = false;
      _activeId = null;
    });
  }

  Widget _supportCard(BuildContext context) {
    final theme = Theme.of(context);
    final supported = _supported == true;
    return Card(
      color: supported
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(supported ? Icons.vibration : Icons.phonelink_erase),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    supported
                        ? tr(
                            context,
                            'Vibration motor detected on this device.',
                            '已检测到本机震动马达。',
                          )
                        : tr(
                            context,
                            'No vibration motor detected on this device. Patterns are shown for reference but cannot be played.',
                            '未检测到本机震动马达。下方模式仅作预览，无法播放。',
                          ),
                  ),
                ),
              ],
            ),
            if (supported) ...[
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  'Platform: ${Platform.operatingSystem} • amplitude control: ${_hasAmplitude ? 'yes' : 'no'}',
                  '平台：${Platform.operatingSystem} • 振幅控制：${_hasAmplitude ? '支持' : '不支持'}',
                ),
                style: theme.textTheme.bodySmall,
              ),
              if (_lastError != null) ...[
                const SizedBox(height: 6),
                Text(
                  tr(context, 'Last error: $_lastError', '最近错误：$_lastError'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _presetsSection(BuildContext context) {
    final enabled = _supported == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Patterns', '震动模式'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final preset in vibrationPresets)
                  ChoiceChip(
                    label: Text(
                      tr(context, preset.englishName, preset.chineseName),
                    ),
                    selected: _activeId == 'preset:${preset.id}',
                    onSelected: enabled ? (_) => _playPreset(preset) : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _customSection(BuildContext context) {
    final enabled = _supported == true;
    final pattern = _customPattern;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Custom pattern', '自定义模式'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customController,
              onChanged: (value) {
                final parsed = parseVibrationPattern(value);
                setState(() {
                  _customPattern = parsed;
                  _customError = value.trim().isEmpty || parsed != null
                      ? null
                      : tr(
                          context,
                          'Enter positive durations in milliseconds separated by commas.',
                          '请输入以逗号分隔的正整数毫秒时长。',
                        );
                });
              },
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  'Pulse and pause durations in ms',
                  '震动与间隔时长（毫秒）',
                ),
                hintText: '200, 100, 200, 100, 500',
                border: const OutlineInputBorder(),
                errorText: _customError,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              pattern == null
                  ? tr(
                      context,
                      'The first value vibrates, the next pauses, and so on.',
                      '第一个数值震动，第二个数值停顿，依次交替。',
                    )
                  : tr(
                      context,
                      '${formatVibrationPattern(pattern)} • total ${vibrationPatternDuration(pattern)} ms',
                      '${formatVibrationPattern(pattern)} • 合计 ${vibrationPatternDuration(pattern)} 毫秒',
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: enabled && pattern != null && pattern.isNotEmpty
                  ? _playCustom
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(tr(context, 'Play', '播放')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionsSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Options', '选项'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(tr(context, 'Vibration style', '震动风格')),
            const SizedBox(height: 8),
            SegmentedButton<VibrationStyle>(
              segments: [
                ButtonSegment(
                  value: VibrationStyle.soft,
                  label: Text(tr(context, 'Soft', '柔和')),
                  icon: const Icon(Icons.waves),
                ),
                ButtonSegment(
                  value: VibrationStyle.standard,
                  label: Text(tr(context, 'Standard', '标准')),
                  icon: const Icon(Icons.horizontal_rule),
                ),
                ButtonSegment(
                  value: VibrationStyle.crisp,
                  label: Text(tr(context, 'Crisp', '哒哒哒')),
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
              selected: {_style},
              onSelectionChanged: (selection) =>
                  setState(() => _style = selection.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Loop', '循环')),
              subtitle: Text(
                tr(
                  context,
                  'Repeat the pattern until stopped.',
                  '持续重复，直到手动停止。',
                ),
              ),
              value: _loop,
              onChanged: (value) => setState(() => _loop = value),
            ),
            if (_hasAmplitude) ...[
              const Divider(),
              Text(
                tr(
                  context,
                  'Strength ${(_amplitude * 100 / 255).round()}%',
                  '强度 ${(_amplitude * 100 / 255).round()}%',
                ),
              ),
              Slider(
                value: _amplitude.toDouble(),
                min: 1,
                max: 255,
                divisions: 254,
                label: '${(_amplitude * 100 / 255).round()}%',
                onChanged: (value) =>
                    setState(() => _amplitude = value.round()),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  tr(
                    context,
                    'Amplitude control requires a device that supports it (usually Android 8+).',
                    '振幅控制需要设备支持（通常为 Android 8+）。',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'Vibrator', '震动器')),
      actions: [
        if (_supported == true)
          IconButton(
            tooltip: tr(context, 'Stop', '停止'),
            onPressed: _playing ? _stop : null,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        toolInfoAction(context, 'vibrator'),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _supported == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                children: [
                  _supportCard(context),
                  const SizedBox(height: 16),
                  _presetsSection(context),
                  const SizedBox(height: 16),
                  _customSection(context),
                  const SizedBox(height: 16),
                  _optionsSection(context),
                ],
              ),
      ),
    ),
  );
}

enum ToneWaveform { sine, square, triangle, saw }

extension ToneWaveformDetails on ToneWaveform {
  String get englishName => switch (this) {
    ToneWaveform.sine => 'Sine',
    ToneWaveform.square => 'Square',
    ToneWaveform.triangle => 'Triangle',
    ToneWaveform.saw => 'Sawtooth',
  };

  String get chineseName => switch (this) {
    ToneWaveform.sine => '正弦波',
    ToneWaveform.square => '方波',
    ToneWaveform.triangle => '三角波',
    ToneWaveform.saw => '锯齿波',
  };

  IconData get icon => switch (this) {
    ToneWaveform.sine => Icons.waves,
    ToneWaveform.square => Icons.crop_square,
    ToneWaveform.triangle => Icons.change_history,
    ToneWaveform.saw => Icons.show_chart,
  };

  WaveForm get nativeWaveform => switch (this) {
    ToneWaveform.sine => WaveForm.sin,
    ToneWaveform.square => WaveForm.fSquare,
    ToneWaveform.triangle => WaveForm.triangle,
    ToneWaveform.saw => WaveForm.fSaw,
  };
}

const double toneMinFrequency = 20;
const double toneMaxFrequency = 20000;
const double motionSicknessToneFrequency = 100;
const String motionSicknessStudyUrl =
    'https://www.jstage.jst.go.jp/article/ehpm/30/0/30_24-00247/_article';
const String motionSicknessStudyTitle =
    'Just 1-min exposure to a pure tone at 100 Hz with daily exposable '
    'sound pressure levels may improve motion sickness';
const List<double> tonePresetFrequencies = [
  20,
  100,
  440,
  1000,
  5000,
  10000,
  20000,
];
const List<Duration?> toneLimitOptions = [
  null,
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 30),
];

double clampToneFrequency(double hz) {
  if (!hz.isFinite) return 440;
  return hz.clamp(toneMinFrequency, toneMaxFrequency).toDouble();
}

double toneSliderToFrequency(double position) {
  final t = position.clamp(0.0, 1.0);
  return toneMinFrequency *
      pow(toneMaxFrequency / toneMinFrequency, t).toDouble();
}

double toneFrequencyToSlider(double hz) =>
    log(clampToneFrequency(hz) / toneMinFrequency) /
    log(toneMaxFrequency / toneMinFrequency);

String formatToneNumber(double hz) {
  final clamped = clampToneFrequency(hz);
  final rounded = clamped.roundToDouble();
  return (clamped - rounded).abs() < 0.05
      ? '${rounded.round()}'
      : clamped.toStringAsFixed(1);
}

String formatToneFrequency(double hz) => '${formatToneNumber(hz)} Hz';

String toneLimitLabel(BuildContext context, Duration? limit) => limit == null
    ? tr(context, 'No limit', '不限时')
    : tr(context, '${limit.inMinutes} min', '${limit.inMinutes} 分钟');

({String name, int octave, int cents})? toneNoteForFrequency(double hz) {
  if (!hz.isFinite || hz <= 0) return null;
  final midi = 69 + 12 * (log(hz / 440) / ln2);
  final rounded = midi.round();
  if (rounded < 0) return null;
  const names = [
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];
  return (
    name: names[rounded % 12],
    octave: rounded ~/ 12 - 1,
    cents: ((midi - rounded) * 100).round(),
  );
}

String formatToneNote(({String name, int octave, int cents}) note) {
  final cents = note.cents == 0
      ? '0'
      : '${note.cents > 0 ? '+' : ''}${note.cents}';
  return '${note.name}${note.octave} $cents ct';
}

String formatCountdown(Duration remaining) {
  final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
  final minutes = seconds ~/ 60;
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

double tonePeriodMilliseconds(double hz) => 1000 / clampToneFrequency(hz);

double toneWavelengthCentimeters(double hz) => 34300 / clampToneFrequency(hz);

enum ToneChannel { both, left, right }

extension ToneChannelDetails on ToneChannel {
  String get englishName => switch (this) {
    ToneChannel.both => 'Both channels',
    ToneChannel.left => 'Left channel',
    ToneChannel.right => 'Right channel',
  };

  String get chineseName => switch (this) {
    ToneChannel.both => '双声道',
    ToneChannel.left => '左声道',
    ToneChannel.right => '右声道',
  };

  IconData get icon => switch (this) {
    ToneChannel.both => Icons.surround_sound_outlined,
    ToneChannel.left => Icons.align_horizontal_left,
    ToneChannel.right => Icons.align_horizontal_right,
  };

  double get pan => switch (this) {
    ToneChannel.both => 0,
    ToneChannel.left => -1,
    ToneChannel.right => 1,
  };
}

class ToneLayer {
  ToneLayer({
    required this.id,
    required this.frequency,
    this.channel = ToneChannel.both,
  }) : sweepFrom = frequency,
       sweepTo = defaultSweepTarget(frequency);

  final String id;
  double frequency;
  ToneChannel channel;
  bool sweepEnabled = false;
  bool sweepInitialized = false;
  double sweepFrom;
  double sweepTo;
  Duration sweepDuration = const Duration(seconds: 10);
  bool sweepRepeat = false;
  bool sweepLogarithmic = true;
}

double defaultSweepTarget(double frequency) {
  final doubled = frequency * 2;
  return clampToneFrequency(
    doubled <= toneMaxFrequency ? doubled : frequency / 2,
  );
}

double toneSweepFrequency({
  required double from,
  required double to,
  required double progress,
  required bool logarithmic,
}) {
  final t = progress.clamp(0.0, 1.0);
  if (logarithmic && from > 0 && to > 0) {
    return (from * pow(to / from, t)).toDouble();
  }
  return from + (to - from) * t;
}

double toneSweepProgress(int elapsedMs, int durationMs, bool repeat) {
  if (durationMs <= 0) return 1;
  if (!repeat) return (elapsedMs / durationMs).clamp(0.0, 1.0);
  final phase = (elapsedMs % (2 * durationMs)) / durationMs;
  return phase <= 1 ? phase : 2 - phase;
}

/// Splits the available headroom between simultaneous layers so that a stack
/// of pure tones does not clip. A layer routed to one channel only competes
/// with the layers on that channel; a both-channel layer competes with the
/// busier side.
Map<String, double> toneLayerGains(List<ToneLayer> layers) {
  var leftCount = 0;
  var rightCount = 0;
  for (final layer in layers) {
    if (layer.channel != ToneChannel.right) leftCount++;
    if (layer.channel != ToneChannel.left) rightCount++;
  }
  final gains = <String, double>{};
  for (final layer in layers) {
    final count = switch (layer.channel) {
      ToneChannel.left => leftCount,
      ToneChannel.right => rightCount,
      ToneChannel.both => max(leftCount, rightCount),
    };
    gains[layer.id] = 1 / max(1, count);
  }
  return gains;
}

class _ToneVoice {
  _ToneVoice({required this.source, required this.handle});

  final AudioSource source;
  final SoundHandle handle;
}

class _ToneSynth {
  final SoLoud _soloud = SoLoud.instance;
  final Map<String, _ToneVoice> _voices = {};
  ToneWaveform _waveform = ToneWaveform.sine;
  double _volume = 0.3;
  int _generation = 0;

  Future<void> start({
    required List<ToneLayer> layers,
    required ToneWaveform waveform,
    required double volume,
  }) async {
    stop(fade: false);
    final generation = ++_generation;
    if (!_soloud.isInitialized) {
      await _soloud.init();
    }
    if (generation != _generation) return;
    _waveform = waveform;
    _volume = volume;
    final snapshot = List<ToneLayer>.of(layers);
    final gains = toneLayerGains(snapshot);
    for (final layer in snapshot) {
      final source = await _soloud.loadWaveform(
        waveform.nativeWaveform,
        false,
        1,
        0,
      );
      if (generation != _generation) {
        await _disposeSource(source);
        return;
      }
      _soloud.setWaveformFreq(source, layer.frequency);
      final handle = _soloud.play(
        source,
        volume: 0,
        pan: layer.channel.pan,
        looping: true,
      );
      _voices[layer.id] = _ToneVoice(source: source, handle: handle);
      _soloud.fadeVolume(
        handle,
        volume * (gains[layer.id] ?? 1),
        const Duration(milliseconds: 60),
      );
    }
  }

  void setFrequency(String id, double frequency) {
    final voice = _voices[id];
    if (voice != null) _soloud.setWaveformFreq(voice.source, frequency);
  }

  void setChannel(String id, ToneChannel channel, List<ToneLayer> layers) {
    final voice = _voices[id];
    if (voice == null) return;
    _soloud.setPan(voice.handle, channel.pan);
    _applyGains(layers);
  }

  void setWaveform(ToneWaveform waveform) {
    _waveform = waveform;
    for (final voice in _voices.values) {
      _soloud.setWaveform(voice.source, waveform.nativeWaveform);
    }
  }

  void setVolume(double volume, List<ToneLayer> layers) {
    _volume = volume;
    _applyGains(layers);
  }

  Future<void> addLayer(ToneLayer layer, List<ToneLayer> layers) async {
    final generation = _generation;
    final source = await _soloud.loadWaveform(
      _waveform.nativeWaveform,
      false,
      1,
      0,
    );
    if (generation != _generation ||
        !layers.any((item) => item.id == layer.id)) {
      await _disposeSource(source);
      return;
    }
    _soloud.setWaveform(source, _waveform.nativeWaveform);
    _soloud.setWaveformFreq(source, layer.frequency);
    final handle = _soloud.play(
      source,
      volume: 0,
      pan: layer.channel.pan,
      looping: true,
    );
    _voices[layer.id] = _ToneVoice(source: source, handle: handle);
    final gains = toneLayerGains(layers);
    for (final entry in _voices.entries) {
      if (entry.key == layer.id) continue;
      _soloud.setVolume(entry.value.handle, _volume * (gains[entry.key] ?? 1));
    }
    _soloud.fadeVolume(
      handle,
      _volume * (gains[layer.id] ?? 1),
      const Duration(milliseconds: 60),
    );
  }

  void removeLayer(String id, List<ToneLayer> layers) {
    final voice = _voices.remove(id);
    if (voice == null) return;
    _stopVoice(voice);
    _applyGains(layers);
  }

  void stop({bool fade = true}) {
    _generation++;
    final voices = _voices.values.toList();
    _voices.clear();
    for (final voice in voices) {
      _stopVoice(voice, fade: fade);
    }
  }

  Future<void> dispose() async {
    _generation++;
    final voices = _voices.values.toList();
    _voices.clear();
    for (final voice in voices) {
      try {
        await _soloud.stop(voice.handle);
      } catch (_) {
        // The engine may already be shutting down.
      }
      await _disposeSource(voice.source);
    }
  }

  void _applyGains(List<ToneLayer> layers) {
    final gains = toneLayerGains(layers);
    for (final entry in _voices.entries) {
      _soloud.setVolume(entry.value.handle, _volume * (gains[entry.key] ?? 1));
    }
  }

  void _stopVoice(_ToneVoice voice, {bool fade = true}) {
    try {
      if (fade) {
        _soloud.fadeVolume(voice.handle, 0, const Duration(milliseconds: 50));
        _soloud.scheduleStop(voice.handle, const Duration(milliseconds: 70));
      } else {
        unawaited(_soloud.stop(voice.handle).catchError((_) {}));
      }
    } catch (_) {
      // The engine may already be shutting down.
    }
    unawaited(_disposeSourceLater(voice.source));
  }

  Future<void> _disposeSourceLater(AudioSource source) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _disposeSource(source);
  }

  Future<void> _disposeSource(AudioSource source) async {
    try {
      await _soloud.disposeSource(source);
    } catch (_) {
      // Ignore teardown errors when the engine is no longer available.
    }
  }
}

class _PlaybackChannel {
  static const _channel = MethodChannel('pockito/background-audio');

  static Future<void> start({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start', {
        'title': title,
        'text': text,
      });
    } catch (_) {
      // Background playback is an enhancement; foreground audio still works.
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}

class _TonePresetChip extends StatelessWidget {
  const _TonePresetChip({
    required this.frequency,
    required this.selected,
    required this.onSelected,
    this.onInfo,
  });

  final double frequency;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    final onInfo = this.onInfo;
    final scheme = Theme.of(context).colorScheme;
    final chip = ChoiceChip(
      label: Text(formatToneFrequency(frequency)),
      selected: selected,
      onSelected: (_) => onSelected(),
      backgroundColor: onInfo == null ? null : Colors.transparent,
      selectedColor: onInfo == null ? null : Colors.transparent,
      surfaceTintColor: onInfo == null ? null : Colors.transparent,
      side: onInfo == null ? null : BorderSide.none,
      shape: onInfo == null ? null : const StadiumBorder(),
      elevation: 0,
      pressElevation: 0,
    );
    if (onInfo == null) return chip;
    return Material(
      color: selected ? scheme.secondaryContainer : scheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? Colors.transparent : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip,
          Container(
            width: 1,
            height: 16,
            color: selected
                ? scheme.onSecondaryContainer.withValues(alpha: 0.2)
                : scheme.outlineVariant,
          ),
          Tooltip(
            message: tr(context, 'Why 100 Hz?', '为什么是 100 Hz？'),
            child: InkWell(
              key: const ValueKey('tone-preset-info-100'),
              onTap: onInfo,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 6, 9, 6),
                child: Icon(
                  Icons.medical_information_outlined,
                  size: 17,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.tertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ToneGeneratorScreen extends StatefulWidget {
  const ToneGeneratorScreen({super.key});

  @override
  State<ToneGeneratorScreen> createState() => _ToneGeneratorScreenState();
}

class _ToneGeneratorScreenState extends State<ToneGeneratorScreen> {
  static const _defaultFrequency = 440.0;
  static const _maxLayers = 4;
  final _synth = _ToneSynth();
  final _frequencyController = TextEditingController(text: '440');
  final _sweepFromController = TextEditingController();
  final _sweepEndController = TextEditingController();
  final _sweepDurationController = TextEditingController();
  final List<ToneLayer> _layers = [
    ToneLayer(id: 'tone-1', frequency: _defaultFrequency),
  ];
  String _activeLayerId = 'tone-1';
  int _nextLayerId = 2;
  double _volume = 0.3;
  ToneWaveform _waveform = ToneWaveform.sine;
  Duration? _limit;
  DateTime? _endsAt;
  Timer? _limitTimer;
  Timer? _sweepTimer;
  final Map<String, double> _liveFrequencies = {};
  final Map<String, DateTime> _sweepStarts = {};
  int _sweepTicks = 0;
  bool _playing = false;
  bool _starting = false;
  String? _error;
  String? _inputError;
  String? _sweepFromError;
  String? _sweepEndError;
  String? _sweepDurationError;
  int _session = 0;

  @override
  void initState() {
    super.initState();
    _syncSweepControllers();
  }

  ToneLayer get _activeLayer => _layers.firstWhere(
    (layer) => layer.id == _activeLayerId,
    orElse: () => _layers.first,
  );

  int get _activeLayerIndex {
    final index = _layers.indexWhere((layer) => layer.id == _activeLayerId);
    return index < 0 ? 0 : index;
  }

  double get _frequency => _activeLayer.frequency;

  double get _displayFrequency =>
      _liveFrequencies[_activeLayer.id] ?? _activeLayer.frequency;

  Duration? get _remaining {
    final endsAt = _endsAt;
    if (endsAt == null) return null;
    final remaining = endsAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  void dispose() {
    _limitTimer?.cancel();
    _sweepTimer?.cancel();
    _session++;
    unawaited(_synth.dispose());
    unawaited(_PlaybackChannel.stop());
    _sweepFromController.dispose();
    _sweepEndController.dispose();
    _sweepDurationController.dispose();
    _frequencyController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting || _playing) return;
    final session = ++_session;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await _synth.start(layers: _layers, waveform: _waveform, volume: _volume);
      if (!mounted) return;
      if (session != _session) {
        // A stop request arrived while the engine was starting. Discard the
        // tone that has just come up instead of leaving it running.
        await _synth.dispose();
        return;
      }
      _beginCountdown();
      setState(() => _playing = true);
      _prepareSweeps();
      unawaited(
        _PlaybackChannel.start(
          title: tr(context, 'Frequency generator', '频率发生器'),
          text: _notificationText(context),
        ),
      );
    } catch (error) {
      if (!mounted || session != _session) return;
      setState(() {
        _error = tr(
          context,
          'Could not start the audio engine: $error',
          '无法启动音频引擎：$error',
        );
      });
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  String _notificationText(BuildContext context) {
    final layer = _activeLayer;
    if (_layers.length == 1 && layer.sweepEnabled) {
      return tr(
        context,
        'Sweeping ${formatToneFrequency(layer.sweepFrom)} to ${formatToneFrequency(layer.sweepTo)}',
        '正在扫频 ${formatToneFrequency(layer.sweepFrom)} 到 ${formatToneFrequency(layer.sweepTo)}',
      );
    }
    if (_layers.length == 1) {
      return tr(
        context,
        'Playing ${formatToneFrequency(layer.frequency)}',
        '正在播放 ${formatToneFrequency(layer.frequency)}',
      );
    }
    return tr(
      context,
      'Playing ${_layers.length} tones',
      '正在播放 ${_layers.length} 个音调',
    );
  }

  void _stop() {
    _session++;
    _limitTimer?.cancel();
    _limitTimer = null;
    _endsAt = null;
    _stopSweeps();
    unawaited(_PlaybackChannel.stop());
    _synth.stop();
    if (!mounted) return;
    setState(() => _playing = false);
  }

  void _setLimit(Duration? limit) {
    _limitTimer?.cancel();
    _limitTimer = null;
    setState(() {
      _limit = limit;
      _endsAt = null;
      if (_playing) _beginCountdown();
    });
  }

  void _beginCountdown() {
    _limitTimer?.cancel();
    _limitTimer = null;
    final limit = _limit;
    if (limit == null) {
      _endsAt = null;
      return;
    }
    _endsAt = DateTime.now().add(limit);
    _limitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = _remaining;
      if (remaining == null || remaining <= Duration.zero) {
        _stop();
        return;
      }
      setState(() {});
    });
  }

  void _applyFrequency(double value, {bool syncField = true}) {
    final frequency = clampToneFrequency(value);
    setState(() {
      _activeLayer.frequency = frequency;
      _inputError = null;
      if (syncField) _frequencyController.text = formatToneNumber(frequency);
      _liveFrequencies[_activeLayer.id] = frequency;
      if (_activeLayer.sweepEnabled) {
        _activeLayer.sweepFrom = frequency;
        _activeLayer.sweepInitialized = true;
        if (_playing) _sweepStarts[_activeLayer.id] = DateTime.now();
      }
    });
    _synth.setFrequency(_activeLayer.id, frequency);
    if (_playing && _activeLayer.sweepEnabled) _ensureSweepTimer();
  }

  void _onFrequencyInput(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < toneMinFrequency ||
        parsed > toneMaxFrequency) {
      setState(() {
        _inputError = tr(
          context,
          'Enter a frequency between 20 and 20,000 Hz.',
          '请输入 20 到 20,000 Hz 之间的频率。',
        );
      });
      return;
    }
    _applyFrequency(parsed, syncField: false);
  }

  void _setVolume(double value) {
    setState(() => _volume = value);
    _synth.setVolume(value, _layers);
  }

  void _setWaveform(ToneWaveform waveform) {
    setState(() => _waveform = waveform);
    _synth.setWaveform(waveform);
  }

  void _selectLayer(ToneLayer layer) {
    if (layer.id == _activeLayerId) return;
    setState(() {
      _activeLayerId = layer.id;
      _frequencyController.text = formatToneNumber(layer.frequency);
      _inputError = null;
      _syncSweepControllers();
    });
  }

  void _addLayer() {
    if (_layers.length >= _maxLayers) return;
    final base = _activeLayer.frequency;
    final doubled = base * 2;
    final frequency = clampToneFrequency(
      doubled <= toneMaxFrequency ? doubled : base / 2,
    );
    final layer = ToneLayer(id: 'tone-${_nextLayerId++}', frequency: frequency);
    setState(() {
      _layers.add(layer);
      _activeLayerId = layer.id;
      _frequencyController.text = formatToneNumber(frequency);
      _inputError = null;
      _liveFrequencies[layer.id] = frequency;
      _syncSweepControllers();
    });
    if (_playing) unawaited(_synth.addLayer(layer, _layers));
  }

  void _removeLayer(ToneLayer layer) {
    if (_layers.length <= 1) return;
    final wasActive = layer.id == _activeLayerId;
    setState(() {
      _layers.removeWhere((item) => item.id == layer.id);
      _liveFrequencies.remove(layer.id);
      _sweepStarts.remove(layer.id);
      if (wasActive) {
        _activeLayerId = _layers.first.id;
        _frequencyController.text = formatToneNumber(_layers.first.frequency);
        _inputError = null;
        _syncSweepControllers();
      }
    });
    if (_playing) _synth.removeLayer(layer.id, _layers);
    _cancelSweepTimerIfIdle();
  }

  void _setLayerChannel(ToneLayer layer, ToneChannel channel) {
    if (layer.channel == channel) return;
    setState(() => layer.channel = channel);
    if (_playing) _synth.setChannel(layer.id, channel, _layers);
  }

  void _syncSweepControllers() {
    final layer = _activeLayer;
    _sweepFromController.text = formatToneNumber(layer.sweepFrom);
    _sweepEndController.text = formatToneNumber(layer.sweepTo);
    _sweepDurationController.text = '${layer.sweepDuration.inSeconds}';
    _sweepFromError = null;
    _sweepEndError = null;
    _sweepDurationError = null;
  }

  void _onSweepFromInput(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < toneMinFrequency ||
        parsed > toneMaxFrequency) {
      setState(() {
        _sweepFromError = tr(
          context,
          'Enter a start frequency between 20 and 20,000 Hz.',
          '请输入 20 到 20,000 Hz 之间的起始频率。',
        );
      });
      return;
    }
    final layer = _activeLayer;
    setState(() {
      layer.sweepFrom = parsed;
      layer.sweepInitialized = true;
      layer.frequency = parsed;
      _liveFrequencies[layer.id] = parsed;
      _frequencyController.text = formatToneNumber(parsed);
      _sweepFromError = null;
    });
    _restartSweep(layer);
  }

  void _onSweepEndInput(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < toneMinFrequency ||
        parsed > toneMaxFrequency) {
      setState(() {
        _sweepEndError = tr(
          context,
          'Enter an end frequency between 20 and 20,000 Hz.',
          '请输入 20 到 20,000 Hz 之间的结束频率。',
        );
      });
      return;
    }
    final layer = _activeLayer;
    setState(() {
      layer.sweepTo = parsed;
      layer.sweepInitialized = true;
      _sweepEndError = null;
    });
    _restartSweep(layer);
  }

  void _setSweepEnd(double value) {
    final frequency = clampToneFrequency(value);
    final layer = _activeLayer;
    setState(() {
      layer.sweepTo = frequency;
      layer.sweepInitialized = true;
      _sweepEndController.text = formatToneNumber(frequency);
      _sweepEndError = null;
    });
    _restartSweep(layer);
  }

  void _onSweepDurationInput(String value) {
    final seconds = int.tryParse(value.trim());
    if (seconds == null || seconds < 1 || seconds > 3600) {
      setState(() {
        _sweepDurationError = tr(
          context,
          'Enter a duration between 1 and 3600 seconds.',
          '请输入 1 到 3600 秒之间的持续时间。',
        );
      });
      return;
    }
    _setSweepSeconds(seconds, syncField: false);
  }

  void _setSweepSeconds(int seconds, {bool syncField = true}) {
    final layer = _activeLayer;
    setState(() {
      layer.sweepDuration = Duration(seconds: seconds);
      _sweepDurationError = null;
      if (syncField) _sweepDurationController.text = '$seconds';
    });
    _restartSweep(layer);
  }

  void _setSweepEnabled(bool enabled) {
    final layer = _activeLayer;
    if (layer.sweepEnabled == enabled) return;
    setState(() {
      if (enabled && !layer.sweepInitialized) {
        layer.sweepFrom = layer.frequency;
        layer.sweepTo = defaultSweepTarget(layer.frequency);
        layer.sweepInitialized = true;
      }
      layer.sweepEnabled = enabled;
      if (enabled) {
        layer.frequency = layer.sweepFrom;
        _liveFrequencies[layer.id] = layer.sweepFrom;
        _frequencyController.text = formatToneNumber(layer.sweepFrom);
        if (_playing) _sweepStarts[layer.id] = DateTime.now();
      } else {
        final current = _liveFrequencies[layer.id] ?? layer.sweepFrom;
        layer.frequency = current;
        _liveFrequencies.remove(layer.id);
        _sweepStarts.remove(layer.id);
        _frequencyController.text = formatToneNumber(current);
        _inputError = null;
      }
      _syncSweepControllers();
    });
    if (_playing) {
      _synth.setFrequency(layer.id, layer.frequency);
      if (enabled) {
        _ensureSweepTimer();
      } else {
        _cancelSweepTimerIfIdle();
      }
    }
  }

  void _setSweepRepeat(bool repeat) {
    final layer = _activeLayer;
    setState(() => layer.sweepRepeat = repeat);
    _restartSweep(layer);
  }

  void _setSweepLogarithmic(bool logarithmic) {
    final layer = _activeLayer;
    setState(() => layer.sweepLogarithmic = logarithmic);
    _restartSweep(layer);
  }

  void _restartSweep(ToneLayer layer) {
    if (!_playing || !layer.sweepEnabled) return;
    _sweepStarts[layer.id] = DateTime.now();
    _liveFrequencies[layer.id] = layer.sweepFrom;
    _synth.setFrequency(layer.id, layer.sweepFrom);
    _ensureSweepTimer();
    if (mounted) setState(() {});
  }

  void _prepareSweeps() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _sweepStarts.clear();
    _liveFrequencies.clear();
    final now = DateTime.now();
    var sweeping = false;
    for (final layer in _layers) {
      if (layer.sweepEnabled) {
        layer.frequency = layer.sweepFrom;
        _liveFrequencies[layer.id] = layer.sweepFrom;
        _sweepStarts[layer.id] = now;
        _synth.setFrequency(layer.id, layer.sweepFrom);
        sweeping = true;
      } else {
        _liveFrequencies[layer.id] = layer.frequency;
      }
    }
    if (!sweeping) return;
    _sweepTicks = 0;
    _sweepTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _tickSweeps(),
    );
  }

  void _ensureSweepTimer() {
    if (_sweepTimer != null || !_playing) return;
    if (!_layers.any((layer) => layer.sweepEnabled)) return;
    _sweepTicks = 0;
    _sweepTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _tickSweeps(),
    );
  }

  void _cancelSweepTimerIfIdle() {
    if (_sweepTimer == null) return;
    if (_playing && _layers.any((layer) => layer.sweepEnabled)) return;
    _sweepTimer?.cancel();
    _sweepTimer = null;
  }

  void _tickSweeps() {
    if (!mounted || !_playing) return;
    final now = DateTime.now();
    var changed = false;
    var running = false;
    for (final layer in _layers) {
      if (!layer.sweepEnabled) continue;
      final start = _sweepStarts[layer.id];
      if (start == null) continue;
      final elapsed = now.difference(start).inMilliseconds;
      final duration = layer.sweepDuration.inMilliseconds;
      final progress = toneSweepProgress(elapsed, duration, layer.sweepRepeat);
      final frequency = toneSweepFrequency(
        from: layer.sweepFrom,
        to: layer.sweepTo,
        progress: progress,
        logarithmic: layer.sweepLogarithmic,
      );
      final previous = _liveFrequencies[layer.id];
      if (previous == null || (frequency - previous).abs() >= 0.01) {
        _liveFrequencies[layer.id] = frequency;
        _synth.setFrequency(layer.id, frequency);
        changed = true;
      }
      if (layer.sweepRepeat || (duration > 0 && elapsed < duration)) {
        running = true;
      } else {
        // One-shot sweep finished: hold at the end frequency.
        _sweepStarts.remove(layer.id);
      }
    }
    if (!running) {
      _sweepTimer?.cancel();
      _sweepTimer = null;
    }
    _sweepTicks++;
    if (changed && _sweepTicks.isEven) setState(() {});
  }

  void _stopSweeps() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    _sweepStarts.clear();
    _liveFrequencies.clear();
  }

  void _showHundredHertzInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text(tr(context, '100 Hz and motion sickness', '100 Hz 与晕车')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    context,
                    'A 2025 study reported that listening to a pure 100 Hz tone for about one minute before motion may reduce signs of motion sickness. The human experiments used 80–85 dBZ (about 61–66 dBA), and the finding is still preliminary.',
                    '一项 2025 年的研究报告称，在晃动或乘车前聆听约 1 分钟 100 Hz 纯音，可能减轻晕车表现。人体实验使用的声压级为 80–85 dBZ（约 61–66 dBA），该结论仍属初步研究。',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  tr(context, 'Reference', '参考文献'),
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  motionSicknessStudyTitle,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Gu Y, Ohgami N, He T, et al. Environmental Health and '
                  'Preventive Medicine. 2025;30:22. '
                  'DOI: 10.1265/ehpm.24-00247',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                _ToolLink(url: motionSicknessStudyUrl),
                const Divider(height: 24),
                Text(
                  tr(
                    context,
                    'The app cannot measure sound pressure level, so the volume slider is not calibrated to the study. Keep the volume comfortable, and do not use this while driving or operating machinery. This is not medical advice.',
                    '应用无法测量声压级，音量滑块与实验条件并不等同。请保持舒适音量，切勿在驾驶或操作机械时使用；本提示不构成医疗建议。',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(tr(context, 'Close', '关闭')),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _setWaveform(ToneWaveform.sine);
                _applyFrequency(motionSicknessToneFrequency);
              },
              icon: const Icon(Icons.check_rounded),
              label: Text(tr(context, 'Use 100 Hz', '使用 100 Hz')),
            ),
          ],
        );
      },
    );
  }

  Widget _toneCard(BuildContext context) {
    final theme = Theme.of(context);
    final layer = _activeLayer;
    final frequency = _displayFrequency;
    final note = toneNoteForFrequency(frequency);
    final period = tonePeriodMilliseconds(frequency);
    final wavelength = toneWavelengthCentimeters(frequency);
    final remaining = _remaining;
    final status = <String>[
      if (_layers.length > 1)
        tr(
          context,
          'Tone ${_activeLayerIndex + 1}/${_layers.length}',
          '音层 ${_activeLayerIndex + 1}/${_layers.length}',
        ),
      if (layer.channel != ToneChannel.both)
        tr(context, layer.channel.englishName, layer.channel.chineseName),
      if (_playing && _sweepStarts.containsKey(layer.id))
        tr(context, 'Sweeping', '扫频中'),
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.graphic_eq, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'Pure tone', '纯音'),
                  style: theme.textTheme.titleMedium,
                ),
                if (status.isNotEmpty) ...[
                  const Spacer(),
                  Text(status, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatToneFrequency(frequency),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    formatToneNote(note),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                context,
                'Period ${period.toStringAsFixed(2)} ms · Wavelength ${wavelength.toStringAsFixed(1)} cm',
                '周期 ${period.toStringAsFixed(2)} 毫秒 · 波长 ${wavelength.toStringAsFixed(1)} 厘米',
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_starting || _playing) ? _stop : _start,
                icon: _starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _playing
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                      ),
                label: Text(
                  (_starting || _playing)
                      ? tr(context, 'Stop', '停止')
                      : tr(context, 'Play', '播放'),
                ),
              ),
            ),
            if (_playing && _limit != null && remaining != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (remaining.inMilliseconds / _limit!.inMilliseconds)
                    .clamp(0.0, 1.0),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  context,
                  'Stops in ${formatCountdown(remaining)}',
                  '剩余 ${formatCountdown(remaining)}',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _layersCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.layers_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'Tones', '音调层'),
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _layers.length < _maxLayers ? _addLayer : null,
                  icon: const Icon(Icons.add),
                  label: Text(tr(context, 'Add', '添加')),
                ),
              ],
            ),
            Text(
              tr(
                context,
                'Mix up to $_maxLayers tones. Send a layer to the left or right channel for a different frequency in each ear.',
                '最多叠加 $_maxLayers 个音调。把某一层设为左或右声道，即可让左右耳听到不同频率。',
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            for (final layer in _layers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                selected: layer.id == _activeLayerId,
                leading: Icon(
                  layer.id == _activeLayerId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: layer.id == _activeLayerId ? scheme.primary : null,
                ),
                title: Text(formatToneFrequency(layer.frequency)),
                subtitle: Text(
                  tr(
                    context,
                    layer.channel.englishName,
                    layer.channel.chineseName,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<ToneChannel>(
                      key: ValueKey('tone-channel-${layer.id}'),
                      tooltip: tr(context, 'Channel', '声道'),
                      icon: Icon(layer.channel.icon),
                      onSelected: (channel) => _setLayerChannel(layer, channel),
                      itemBuilder: (context) => [
                        for (final channel in ToneChannel.values)
                          PopupMenuItem(
                            value: channel,
                            child: Row(
                              children: [
                                Icon(channel.icon, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  tr(
                                    context,
                                    channel.englishName,
                                    channel.chineseName,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    IconButton(
                      tooltip: tr(context, 'Remove tone', '删除音调层'),
                      onPressed: _layers.length > 1
                          ? () => _removeLayer(layer)
                          : null,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                onTap: () => _selectLayer(layer),
              ),
          ],
        ),
      ),
    );
  }

  Widget _frequencyCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _layers.length > 1
                  ? tr(
                      context,
                      'Frequency · Tone ${_activeLayerIndex + 1}',
                      '频率 · 音层 ${_activeLayerIndex + 1}',
                    )
                  : tr(context, 'Frequency', '频率'),
              style: theme.textTheme.titleMedium,
            ),
            Slider(
              value: toneFrequencyToSlider(_frequency),
              label: formatToneFrequency(_frequency),
              onChanged: (value) =>
                  _applyFrequency(toneSliderToFrequency(value)),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('tone-frequency-field'),
                    controller: _frequencyController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: _onFrequencyInput,
                    onSubmitted: (value) {
                      final parsed = double.tryParse(value.trim());
                      _applyFrequency(parsed ?? _frequency);
                    },
                    decoration: InputDecoration(
                      labelText: tr(context, 'Exact frequency', '精确频率'),
                      suffixText: 'Hz',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText: _inputError,
                      errorMaxLines: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: tr(context, 'Decrease by 1 Hz', '减少 1 Hz'),
                  onPressed: () => _applyFrequency(_frequency - 1),
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: tr(context, 'Increase by 1 Hz', '增加 1 Hz'),
                  onPressed: () => _applyFrequency(_frequency + 1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _applyFrequency(_frequency - 10),
                  child: const Text('−10'),
                ),
                OutlinedButton(
                  onPressed: () => _applyFrequency(_frequency + 10),
                  child: const Text('+10'),
                ),
                OutlinedButton(
                  onPressed: () => _applyFrequency(_frequency / 2),
                  child: const Text('÷2'),
                ),
                OutlinedButton(
                  onPressed: () => _applyFrequency(_frequency * 2),
                  child: const Text('×2'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              tr(context, 'Presets', '预设'),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in tonePresetFrequencies)
                  _TonePresetChip(
                    frequency: preset,
                    selected: (_frequency - preset).abs() < 0.5,
                    onSelected: () => _applyFrequency(preset),
                    onInfo: preset == motionSicknessToneFrequency
                        ? () => _showHundredHertzInfo(context)
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _sweepDurationLabel(BuildContext context, int seconds) =>
      tr(context, '$seconds s', '$seconds 秒');

  Widget _sweepCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final layer = _activeLayer;
    final title = _layers.length > 1
        ? tr(
            context,
            'Frequency sweep · Tone ${_activeLayerIndex + 1}',
            '频率扫频 · 音层 ${_activeLayerIndex + 1}',
          )
        : tr(context, 'Frequency sweep', '频率扫频');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Switch(
                  key: const ValueKey('tone-sweep-switch'),
                  value: layer.sweepEnabled,
                  onChanged: _setSweepEnabled,
                ),
              ],
            ),
            Text(
              tr(
                context,
                'Glide the selected tone from a start frequency to an end frequency over a set time.',
                '让当前音层在设定时间内从起始频率变化到结束频率。',
              ),
              style: theme.textTheme.bodySmall,
            ),
            if (!layer.sweepEnabled) ...[
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  'Turn the sweep on to set its range and duration. It restarts whenever playback begins.',
                  '开启后可设置扫频范围与持续时间；每次开始播放时都会从头扫频。',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('tone-sweep-from'),
                      controller: _sweepFromController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: _onSweepFromInput,
                      decoration: InputDecoration(
                        labelText: tr(context, 'Start', '起始频率'),
                        suffixText: 'Hz',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        errorText: _sweepFromError,
                        errorMaxLines: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('tone-sweep-end'),
                      controller: _sweepEndController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: _onSweepEndInput,
                      decoration: InputDecoration(
                        labelText: tr(context, 'End', '结束频率'),
                        suffixText: 'Hz',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        errorText: _sweepEndError,
                        errorMaxLines: 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _setSweepEnd(layer.sweepFrom * 2),
                    child: const Text('×2'),
                  ),
                  OutlinedButton(
                    onPressed: () => _setSweepEnd(layer.sweepFrom * 4),
                    child: const Text('×4'),
                  ),
                  OutlinedButton(
                    onPressed: () => _setSweepEnd(layer.sweepFrom / 2),
                    child: const Text('÷2'),
                  ),
                  OutlinedButton(
                    onPressed: () => _setSweepEnd(toneMaxFrequency),
                    child: Text(tr(context, 'Max', '最高')),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('tone-sweep-duration'),
                controller: _sweepDurationController,
                keyboardType: TextInputType.number,
                onChanged: _onSweepDurationInput,
                decoration: InputDecoration(
                  labelText: tr(context, 'Duration', '持续时间'),
                  suffixText: 's',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  errorText: _sweepDurationError,
                  errorMaxLines: 2,
                  helperText: tr(context, '1–3600 seconds', '1–3600 秒'),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final seconds in const [5, 10, 30, 60, 300])
                    ChoiceChip(
                      label: Text(_sweepDurationLabel(context, seconds)),
                      selected: layer.sweepDuration.inSeconds == seconds,
                      onSelected: (_) => _setSweepSeconds(seconds),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(tr(context, 'Linear', '线性')),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(tr(context, 'Logarithmic', '对数')),
                  ),
                ],
                selected: {layer.sweepLogarithmic},
                onSelectionChanged: (selection) =>
                    _setSweepLogarithmic(selection.first),
              ),
              SwitchListTile(
                key: const ValueKey('tone-sweep-repeat'),
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'Back and forth', '往返扫频')),
                subtitle: Text(
                  tr(
                    context,
                    'Reverse at the end instead of stopping.',
                    '到达结束频率后反向返回，而不是停止。',
                  ),
                ),
                value: layer.sweepRepeat,
                onChanged: _setSweepRepeat,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _waveformCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Waveform', '波形'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final waveform in ToneWaveform.values)
                  ChoiceChip(
                    avatar: Icon(waveform.icon, size: 18),
                    label: Text(
                      tr(context, waveform.englishName, waveform.chineseName),
                    ),
                    selected: _waveform == waveform,
                    onSelected: (_) => _setWaveform(waveform),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _playbackTimeCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'Playback time', '播放时间'),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in toneLimitOptions)
                  ChoiceChip(
                    label: Text(toneLimitLabel(context, option)),
                    selected: _limit == option,
                    onSelected: (_) => _setLimit(option),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.headphones_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(
                      context,
                      'Audio keeps playing when you switch apps or lock the screen. On Android a playback notification keeps it alive.',
                      '切换应用或锁屏后，音频会继续播放。Android 会显示一条播放通知以保持运行。',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _volumeCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_up_outlined),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'Volume', '音量'),
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text('${(_volume * 100).round()}%'),
              ],
            ),
            Slider(
              value: _volume,
              divisions: 100,
              label: '${(_volume * 100).round()}%',
              onChanged: _setVolume,
            ),
            Text(
              tr(
                context,
                'Start at a low volume. High frequencies can be uncomfortable, and prolonged listening at loud levels may damage your hearing.',
                '请从低音量开始。高频可能刺耳，长时间大音量聆听可能损伤听力。',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'Frequency Generator', '频率发生器')),
      actions: [
        if (_playing)
          IconButton(
            tooltip: tr(context, 'Stop', '停止'),
            onPressed: _stop,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        toolInfoAction(context, 'tone-generator'),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          children: [
            _toneCard(context),
            const SizedBox(height: 16),
            _layersCard(context),
            const SizedBox(height: 16),
            if (!_activeLayer.sweepEnabled) ...[
              _frequencyCard(context),
              const SizedBox(height: 16),
            ],
            _sweepCard(context),
            const SizedBox(height: 16),
            _waveformCard(context),
            const SizedBox(height: 16),
            _playbackTimeCard(context),
            const SizedBox(height: 16),
            _volumeCard(context),
          ],
        ),
      ),
    ),
  );
}

const double speakerCleanerMinFrequency = 60;
const double speakerCleanerMaxFrequency = 1000;
const double speakerCleanerDefaultFrequency = 165;
const int speakerCleanerMinBurstMs = 100;
const int speakerCleanerMaxBurstMs = 1500;
const int speakerCleanerMinPauseMs = 50;
const int speakerCleanerMaxPauseMs = 1000;
const List<Duration> speakerCleanerDurations = [
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 30),
  Duration(seconds: 45),
];

double clampSpeakerCleanerFrequency(double hz) {
  if (!hz.isFinite) return speakerCleanerDefaultFrequency;
  return hz
      .clamp(speakerCleanerMinFrequency, speakerCleanerMaxFrequency)
      .toDouble();
}

double speakerCleanerSliderToFrequency(double position) {
  final t = position.clamp(0.0, 1.0);
  return speakerCleanerMinFrequency *
      pow(
        speakerCleanerMaxFrequency / speakerCleanerMinFrequency,
        t,
      ).toDouble();
}

double speakerCleanerFrequencyToSlider(double hz) =>
    log(clampSpeakerCleanerFrequency(hz) / speakerCleanerMinFrequency) /
    log(speakerCleanerMaxFrequency / speakerCleanerMinFrequency);

bool speakerCleanerBurstActive(
  int elapsedMs, {
  required int burstMs,
  required int pauseMs,
}) {
  final cycle = max(1, burstMs + pauseMs);
  return (elapsedMs < 0 ? 0 : elapsedMs) % cycle < burstMs;
}

int speakerCleanerTotalPulses(
  Duration duration, {
  required int burstMs,
  required int pauseMs,
}) {
  final cycle = max(1, burstMs + pauseMs);
  return max(1, (duration.inMilliseconds + cycle - 1) ~/ cycle);
}

int speakerCleanerPulseIndex(
  int elapsedMs, {
  required int burstMs,
  required int pauseMs,
}) {
  final cycle = max(1, burstMs + pauseMs);
  return (elapsedMs < 0 ? 0 : elapsedMs) ~/ cycle + 1;
}

String formatSpeakerCleanerDuration(int ms) {
  if (ms >= 1000) {
    final seconds = ms / 1000;
    return seconds == seconds.roundToDouble()
        ? '${seconds.round()} s'
        : '${seconds.toStringAsFixed(1)} s';
  }
  return '$ms ms';
}

String speakerCleanerDurationLabel(BuildContext context, Duration duration) =>
    tr(context, '${duration.inSeconds} s', '${duration.inSeconds} 秒');

class SpeakerCleanerRhythm {
  const SpeakerCleanerRhythm({
    required this.id,
    required this.englishName,
    required this.chineseName,
    required this.burstMs,
    required this.pauseMs,
  });

  final String id;
  final String englishName;
  final String chineseName;
  final int burstMs;
  final int pauseMs;
}

const speakerCleanerRhythms = <SpeakerCleanerRhythm>[
  SpeakerCleanerRhythm(
    id: 'gentle',
    englishName: 'Gentle',
    chineseName: '轻柔',
    burstMs: 600,
    pauseMs: 400,
  ),
  SpeakerCleanerRhythm(
    id: 'standard',
    englishName: 'Standard',
    chineseName: '标准',
    burstMs: 800,
    pauseMs: 250,
  ),
  SpeakerCleanerRhythm(
    id: 'strong',
    englishName: 'Strong',
    chineseName: '强劲',
    burstMs: 1000,
    pauseMs: 200,
  ),
  SpeakerCleanerRhythm(
    id: 'rapid',
    englishName: 'Rapid',
    chineseName: '快速',
    burstMs: 350,
    pauseMs: 150,
  ),
];

class _SpeakerCleanerSynth {
  final SoLoud _soloud = SoLoud.instance;
  AudioSource? _source;
  SoundHandle? _handle;
  double _volume = 0.7;
  bool _audible = false;
  int _generation = 0;

  Future<void> start({
    required double frequency,
    required double volume,
  }) async {
    await stop(fade: false);
    final generation = ++_generation;
    if (!_soloud.isInitialized) {
      await _soloud.init();
    }
    if (generation != _generation) return;
    final source = await _soloud.loadWaveform(WaveForm.sin, false, 1, 0);
    if (generation != _generation) {
      await _disposeSource(source);
      return;
    }
    _soloud.setWaveformFreq(source, frequency);
    final handle = _soloud.play(source, volume: 0, looping: true);
    _source = source;
    _handle = handle;
    _volume = volume;
    _audible = true;
    _soloud.fadeVolume(handle, volume, const Duration(milliseconds: 20));
  }

  void setFrequency(double frequency) {
    final source = _source;
    if (source != null) _soloud.setWaveformFreq(source, frequency);
  }

  void setVolume(double volume) {
    _volume = volume;
    final handle = _handle;
    if (handle != null && _audible) {
      _soloud.fadeVolume(handle, volume, const Duration(milliseconds: 60));
    }
  }

  void setAudible(bool audible) {
    if (_audible == audible) return;
    _audible = audible;
    final handle = _handle;
    if (handle == null) return;
    _soloud.fadeVolume(
      handle,
      audible ? _volume : 0,
      const Duration(milliseconds: 10),
    );
  }

  Future<void> stop({bool fade = true}) async {
    _generation++;
    final handle = _handle;
    final source = _source;
    _handle = null;
    _source = null;
    _audible = false;
    if (handle != null) {
      try {
        if (fade) {
          _soloud.fadeVolume(handle, 0, const Duration(milliseconds: 30));
          _soloud.scheduleStop(handle, const Duration(milliseconds: 50));
        } else {
          await _soloud.stop(handle);
        }
      } catch (_) {
        // The engine may already be shutting down.
      }
    }
    if (source != null) {
      unawaited(_disposeLater(source));
    }
  }

  Future<void> _disposeLater(AudioSource source) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _disposeSource(source);
  }

  Future<void> _disposeSource(AudioSource source) async {
    try {
      await _soloud.disposeSource(source);
    } catch (_) {
      // Ignore teardown errors when the engine is no longer available.
    }
  }
}

class SpeakerCleanerScreen extends StatefulWidget {
  const SpeakerCleanerScreen({super.key});

  @override
  State<SpeakerCleanerScreen> createState() => _SpeakerCleanerScreenState();
}

class _SpeakerCleanerScreenState extends State<SpeakerCleanerScreen> {
  static const _timeout = Duration(seconds: 2);
  final _synth = _SpeakerCleanerSynth();
  final _frequencyController = TextEditingController(
    text: '${speakerCleanerDefaultFrequency.round()}',
  );
  double _frequency = speakerCleanerDefaultFrequency;
  String? _frequencyError;
  int _burstMs = 800;
  int _pauseMs = 250;
  int _durationSeconds = 20;
  double _volume = 0.7;
  bool? _vibrationSupported;
  bool _hasAmplitude = false;
  bool _vibrationEnabled = true;
  bool _vibrationPending = false;
  bool _playing = false;
  bool _starting = false;
  bool _completed = false;
  bool _burstOn = false;
  String? _error;
  Stopwatch? _stopwatch;
  Timer? _pulseTimer;
  int _uiTicks = 0;
  int _session = 0;

  Duration get _duration => Duration(seconds: _durationSeconds);

  Duration get _remaining {
    final stopwatch = _stopwatch;
    if (stopwatch == null) return _duration;
    final remaining = _duration - stopwatch.elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  double get _progress {
    final stopwatch = _stopwatch;
    if (stopwatch == null) return _completed ? 1 : 0;
    return (stopwatch.elapsedMilliseconds / _duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  int get _totalPulses => speakerCleanerTotalPulses(
    _duration,
    burstMs: _burstMs,
    pauseMs: _pauseMs,
  );

  int get _pulseNumber {
    final stopwatch = _stopwatch;
    if (stopwatch == null) return 0;
    return min(
      _totalPulses,
      speakerCleanerPulseIndex(
        stopwatch.elapsedMilliseconds,
        burstMs: _burstMs,
        pauseMs: _pauseMs,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _checkVibrationSupport();
  }

  @override
  void dispose() {
    _session++;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _stopwatch?.stop();
    _stopwatch = null;
    unawaited(_synth.stop(fade: false));
    unawaited(_VibratorChannel.cancel().catchError((_) {}));
    unawaited(_PlaybackChannel.stop());
    _frequencyController.dispose();
    super.dispose();
  }

  Future<void> _checkVibrationSupport() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      // Desktop platforms do not register the vibrator channel.
      if (!mounted) return;
      setState(() {
        _vibrationSupported = false;
        _vibrationEnabled = false;
      });
      return;
    }
    var supported = false;
    var amplitude = false;
    try {
      supported = await _VibratorChannel.isAvailable().timeout(_timeout);
      if (supported) {
        amplitude = await _VibratorChannel.hasAmplitudeControl().timeout(
          _timeout,
        );
      }
    } catch (_) {
      supported = false;
    }
    if (!mounted) return;
    setState(() {
      _vibrationSupported = supported;
      _hasAmplitude = amplitude;
      if (!supported) _vibrationEnabled = false;
    });
    if (supported && _playing && _vibrationEnabled) {
      if (_burstOn) {
        unawaited(_startVibration());
      } else {
        _vibrationPending = true;
      }
    }
  }

  Future<void> _start() async {
    if (_starting || _playing) return;
    final session = ++_session;
    setState(() {
      _starting = true;
      _error = null;
      _completed = false;
    });
    try {
      await _synth.start(frequency: _frequency, volume: _volume);
      if (!mounted) return;
      if (session != _session) {
        await _synth.stop(fade: false);
        return;
      }
      _synth.setFrequency(_frequency);
      _stopwatch = Stopwatch()..start();
      _uiTicks = 0;
      _burstOn = true;
      _pulseTimer = Timer.periodic(const Duration(milliseconds: 20), _tick);
      setState(() => _playing = true);
      if (_vibrationEnabled && _vibrationSupported == true) {
        unawaited(_startVibration());
      }
      unawaited(
        _PlaybackChannel.start(
          title: tr(context, 'Speaker cleaner', '扬声器排水'),
          text: tr(
            context,
            'Pulsing at ${formatToneFrequency(_frequency)}',
            '以 ${formatToneFrequency(_frequency)} 脉冲排水',
          ),
        ),
      );
    } catch (error) {
      if (!mounted || session != _session) return;
      setState(() {
        _error = tr(
          context,
          'Could not start the audio engine: $error',
          '无法启动音频引擎：$error',
        );
      });
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _tick(Timer timer) {
    final stopwatch = _stopwatch;
    if (stopwatch == null) return;
    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed >= _duration.inMilliseconds) {
      _finish();
      return;
    }
    final on = speakerCleanerBurstActive(
      elapsed,
      burstMs: _burstMs,
      pauseMs: _pauseMs,
    );
    final changed = on != _burstOn;
    if (changed) {
      _burstOn = on;
      _synth.setAudible(on);
      if (on && _vibrationPending) {
        _vibrationPending = false;
        unawaited(_startVibration());
      }
    }
    _uiTicks++;
    if (changed || _uiTicks % 5 == 0) {
      if (mounted) setState(() {});
    }
  }

  void _finish() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _stopwatch?.stop();
    _stopwatch = null;
    _synth.setAudible(false);
    unawaited(_synth.stop());
    _cancelVibration();
    unawaited(_PlaybackChannel.stop());
    if (!mounted) return;
    setState(() {
      _playing = false;
      _burstOn = false;
      _completed = true;
    });
  }

  void _stop() {
    _session++;
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _stopwatch?.stop();
    _stopwatch = null;
    _synth.setAudible(false);
    unawaited(_synth.stop(fade: false));
    _cancelVibration();
    unawaited(_PlaybackChannel.stop());
    if (!mounted) return;
    setState(() {
      _playing = false;
      _burstOn = false;
      _completed = false;
    });
  }

  void _cancelVibration() {
    _vibrationPending = false;
    unawaited(_VibratorChannel.cancel().catchError((_) {}));
  }

  Future<void> _startVibration() async {
    try {
      await _VibratorChannel.vibrate(
        pattern: [_burstMs, _pauseMs],
        repeat: 0,
        amplitude: _hasAmplitude ? 200 : -1,
        sharpness: 0.6,
      );
    } catch (_) {
      // Vibration is optional; audio pulses keep working without it.
    }
  }

  void _setVibration(bool value) {
    if (_vibrationSupported != true) return;
    setState(() => _vibrationEnabled = value);
    if (!_playing) {
      _vibrationPending = false;
      return;
    }
    if (!value) {
      _cancelVibration();
      return;
    }
    if (_burstOn) {
      unawaited(_startVibration());
    } else {
      _vibrationPending = true;
    }
  }

  void _applyFrequency(double value, {bool syncField = true}) {
    final frequency = clampSpeakerCleanerFrequency(value);
    setState(() {
      _frequency = frequency;
      _frequencyError = null;
      if (syncField) _frequencyController.text = formatToneNumber(frequency);
    });
    _synth.setFrequency(frequency);
  }

  void _onFrequencyInput(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < speakerCleanerMinFrequency ||
        parsed > speakerCleanerMaxFrequency) {
      setState(() {
        _frequencyError = tr(
          context,
          'Enter a frequency between 60 and 1,000 Hz.',
          '请输入 60 到 1,000 Hz 之间的频率。',
        );
      });
      return;
    }
    setState(() {
      _frequency = clampSpeakerCleanerFrequency(parsed);
      _frequencyError = null;
    });
    _synth.setFrequency(_frequency);
  }

  void _setRhythm(SpeakerCleanerRhythm rhythm) {
    setState(() {
      _burstMs = rhythm.burstMs;
      _pauseMs = rhythm.pauseMs;
    });
  }

  void _setBurst(int value) {
    setState(() => _burstMs = value);
  }

  void _setPause(int value) {
    setState(() => _pauseMs = value);
  }

  void _setVolume(double value) {
    setState(() => _volume = value);
    _synth.setVolume(value);
  }

  Widget _statusCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = _error != null
        ? _error!
        : _starting
        ? tr(context, 'Starting the audio engine…', '正在启动音频引擎…')
        : _playing
        ? tr(
            context,
            'Pulse $_pulseNumber of $_totalPulses · '
                '${formatCountdown(_remaining)} left',
            '第 $_pulseNumber / $_totalPulses 次脉冲 · '
                '剩余 ${formatCountdown(_remaining)}',
          )
        : _completed
        ? tr(
            context,
            'Cycle complete. Repeat if water remains.',
            '本轮完成。若仍有水，可再运行一次。',
          )
        : tr(context, 'Ready when you are.', '准备就绪。');
    return Card(
      color: _completed ? scheme.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AnimatedScale(
                  scale: _playing && _burstOn ? 1.15 : 1,
                  duration: const Duration(milliseconds: 90),
                  child: Icon(
                    Icons.speaker_outlined,
                    size: 32,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, 'Cleaning pulse', '排水脉冲'),
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        tr(
                          context,
                          'Low-frequency pulses push water out of the speaker grille.',
                          '低频脉冲把水从扬声器开孔震出来。',
                        ),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_starting || _playing) ? _stop : _start,
                icon: _starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _playing
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                      ),
                label: Text(
                  (_starting || _playing)
                      ? tr(context, 'Stop', '停止')
                      : tr(context, 'Start cleaning', '开始排水'),
                ),
              ),
            ),
            if (_playing || _completed) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _progress,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              status,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _error != null ? scheme.error : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rhythmCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pattern, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'Pulse rhythm', '脉冲节奏'),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                context,
                'Each pulse alternates a tone burst with silence.',
                '每次脉冲由一段发声和一段静音组成。',
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final rhythm in speakerCleanerRhythms)
                  ChoiceChip(
                    key: ValueKey('speaker-cleaner-rhythm-${rhythm.id}'),
                    label: Text(
                      tr(context, rhythm.englishName, rhythm.chineseName),
                    ),
                    selected:
                        _burstMs == rhythm.burstMs &&
                        _pauseMs == rhythm.pauseMs,
                    onSelected: _playing ? null : (_) => _setRhythm(rhythm),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: _burstMs,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  flex: _pauseMs,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                context,
                '${formatSpeakerCleanerDuration(_burstMs)} tone · '
                    '${formatSpeakerCleanerDuration(_pauseMs)} pause',
                '${formatSpeakerCleanerDuration(_burstMs)} 发声 · '
                    '${formatSpeakerCleanerDuration(_pauseMs)} 静音',
              ),
              key: const ValueKey('speaker-cleaner-rhythm-summary'),
              style: theme.textTheme.bodySmall,
            ),
            if (_playing) ...[
              const SizedBox(height: 4),
              Text(
                tr(
                  context,
                  'Rhythm is locked while the pulses run. Stop to change it.',
                  '脉冲运行期间节奏已锁定，停止后可调整。',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            _msSlider(
              context,
              key: const ValueKey('speaker-cleaner-burst-slider'),
              englishLabel: 'Burst',
              chineseLabel: '发声',
              value: _burstMs,
              min: speakerCleanerMinBurstMs,
              max: speakerCleanerMaxBurstMs,
              onChanged: _playing ? null : _setBurst,
            ),
            _msSlider(
              context,
              key: const ValueKey('speaker-cleaner-pause-slider'),
              englishLabel: 'Pause',
              chineseLabel: '静音',
              value: _pauseMs,
              min: speakerCleanerMinPauseMs,
              max: speakerCleanerMaxPauseMs,
              onChanged: _playing ? null : _setPause,
            ),
          ],
        ),
      ),
    );
  }

  Widget _msSlider(
    BuildContext context, {
    required Key key,
    required String englishLabel,
    required String chineseLabel,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int>? onChanged,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            tr(context, englishLabel, chineseLabel),
            style: theme.textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: Slider(
            key: key,
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min) ~/ 50,
            label: formatSpeakerCleanerDuration(value),
            onChanged: onChanged == null
                ? null
                : (position) => onChanged(position.round()),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            formatSpeakerCleanerDuration(value),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _frequencyCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.waves, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'Tone frequency', '音调频率'),
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  formatToneFrequency(_frequency),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                context,
                'Lower frequencies move the speaker cone further. '
                    '165 Hz is a useful starting point.',
                '频率越低，扬声器振膜位移越大。165 Hz 是常用的起点。',
              ),
              style: theme.textTheme.bodySmall,
            ),
            Slider(
              key: const ValueKey('speaker-cleaner-frequency-slider'),
              value: speakerCleanerFrequencyToSlider(_frequency),
              label: formatToneFrequency(_frequency),
              onChanged: (position) =>
                  _applyFrequency(speakerCleanerSliderToFrequency(position)),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hz in const [
                  100.0,
                  165.0,
                  200.0,
                  300.0,
                  500.0,
                  800.0,
                ])
                  ChoiceChip(
                    key: ValueKey('speaker-cleaner-frequency-${hz.round()}'),
                    label: Text(formatToneFrequency(hz)),
                    selected: (_frequency - hz).abs() < 0.5,
                    onSelected: (_) => _applyFrequency(hz),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('speaker-cleaner-frequency-field'),
              controller: _frequencyController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: _onFrequencyInput,
              decoration: InputDecoration(
                labelText: tr(context, 'Exact frequency', '精确频率'),
                suffixText: 'Hz',
                isDense: true,
                border: const OutlineInputBorder(),
                errorText: _frequencyError,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                context,
                'You can retune the frequency while the pulses run.',
                '运行期间仍可实时调整频率。',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _durationCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'Cleaning time', '排水时长'),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final duration in speakerCleanerDurations)
                  ChoiceChip(
                    key: ValueKey(
                      'speaker-cleaner-duration-${duration.inSeconds}',
                    ),
                    label: Text(speakerCleanerDurationLabel(context, duration)),
                    selected: _durationSeconds == duration.inSeconds,
                    onSelected: _playing
                        ? null
                        : (_) => setState(
                            () => _durationSeconds = duration.inSeconds,
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                context,
                'Stops automatically when the cycle ends. '
                    'Keep the speaker facing downward.',
                '一轮结束后会自动停止。请保持扬声器朝下。',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _vibrationCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final support = _vibrationSupported;
    return Card(
      child: SwitchListTile(
        key: const ValueKey('speaker-cleaner-vibration'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        secondary: Icon(
          Icons.vibration,
          color: support == true ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(tr(context, 'Sync vibration', '同步震动')),
        subtitle: Text(
          support == null
              ? tr(context, 'Checking the vibration motor…', '正在检测震动马达…')
              : support
              ? tr(
                  context,
                  'Pulse the vibration motor with each tone burst.',
                  '每次音频脉冲时同步震动。',
                )
              : tr(
                  context,
                  'No vibration motor on this device; audio pulses still work.',
                  '本机没有震动马达，仍可播放音频脉冲。',
                ),
        ),
        value: support == true && _vibrationEnabled,
        onChanged: support == true ? _setVibration : null,
      ),
    );
  }

  Widget _volumeCard(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_up_outlined),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'Volume', '音量'),
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text('${(_volume * 100).round()}%'),
              ],
            ),
            Slider(
              value: _volume,
              divisions: 100,
              label: '${(_volume * 100).round()}%',
              onChanged: _setVolume,
            ),
            Text(
              tr(
                context,
                'Start around 60–70%. Very loud low frequencies can '
                    'distort or damage the speaker; stop if you hear buzzing.',
                '建议从 60–70% 开始。过大的低频音量可能让扬声器破音或受损；'
                    '如出现破音请立即停止。',
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _instructionsCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'How to use it', '使用方法'),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _step(
              context,
              1,
              'Remove the case, then face the speaker downward over a dry cloth.',
              '取下保护壳，把扬声器朝下，放在干布上。',
            ),
            const SizedBox(height: 8),
            _step(
              context,
              2,
              'Set a volume that makes the speaker rattle without distorting.',
              '把音量调到能感到明显震动、但不破音的水平。',
            ),
            const SizedBox(height: 8),
            _step(
              context,
              3,
              'Run one cycle. If water remains, repeat once or twice and let it air-dry.',
              '运行一轮；若仍有水，可再运行一到两次，然后自然风干。',
            ),
            const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: scheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(
                      context,
                      'Do not insert anything into the speaker grille. '
                          'Do not use this tool if the speaker is damaged, '
                          'the device is not water-resistant, or it has been '
                          'submerged; power it off and seek repair instead.',
                      '不要用物体插入扬声器开孔。若扬声器已损坏、设备不具备防水能力，'
                          '或曾严重进水，请勿使用本工具；应尽快断电并送修。',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(
    BuildContext context,
    int number,
    String english,
    String chinese,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            tr(context, english, chinese),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'Speaker Cleaner', '扬声器排水')),
      actions: [
        if (_playing)
          IconButton(
            tooltip: tr(context, 'Stop', '停止'),
            onPressed: _stop,
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        toolInfoAction(context, 'speaker-cleaner'),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          children: [
            _statusCard(context),
            const SizedBox(height: 16),
            _rhythmCard(context),
            const SizedBox(height: 16),
            _frequencyCard(context),
            const SizedBox(height: 16),
            _durationCard(context),
            const SizedBox(height: 16),
            _vibrationCard(context),
            const SizedBox(height: 16),
            _volumeCard(context),
            const SizedBox(height: 16),
            _instructionsCard(context),
          ],
        ),
      ),
    ),
  );
}

enum ClockLayout { auto, portrait, landscape }

extension ClockLayoutDetails on ClockLayout {
  String get englishName => switch (this) {
    ClockLayout.auto => 'Auto',
    ClockLayout.portrait => 'Portrait',
    ClockLayout.landscape => 'Landscape',
  };

  String get chineseName => switch (this) {
    ClockLayout.auto => '自动',
    ClockLayout.portrait => '竖屏',
    ClockLayout.landscape => '横屏',
  };
}

enum ClockThemeMode { app, light, dark }

extension ClockThemeModeDetails on ClockThemeMode {
  String get englishName => switch (this) {
    ClockThemeMode.app => 'App',
    ClockThemeMode.light => 'Light',
    ClockThemeMode.dark => 'Dark',
  };

  String get chineseName => switch (this) {
    ClockThemeMode.app => '应用',
    ClockThemeMode.light => '浅色',
    ClockThemeMode.dark => '深色',
  };
}

class ClockAccentPreset {
  const ClockAccentPreset(
    this.id,
    this.englishName,
    this.chineseName,
    this.color,
  );

  final String id;
  final String englishName;
  final String chineseName;
  final int color;
}

const clockAccentPresets = <ClockAccentPreset>[
  ClockAccentPreset('teal', 'Teal', '青色', 0xff007c72),
  ClockAccentPreset('blue', 'Blue', '蓝色', 0xff1565c0),
  ClockAccentPreset('indigo', 'Indigo', '靛蓝', 0xff3949ab),
  ClockAccentPreset('purple', 'Purple', '紫色', 0xff7b1fa2),
  ClockAccentPreset('pink', 'Pink', '粉色', 0xffc2185b),
  ClockAccentPreset('orange', 'Orange', '橙色', 0xffe65100),
  ClockAccentPreset('green', 'Green', '绿色', 0xff2e7d32),
  ClockAccentPreset('slate', 'Slate', '石墨', 0xff455a64),
];

enum ClockFace { analog, flip, binary, big, segment }

extension ClockFaceDetails on ClockFace {
  String get englishName => switch (this) {
    ClockFace.analog => 'Analog',
    ClockFace.flip => 'Flip',
    ClockFace.binary => 'Binary',
    ClockFace.big => 'Big digits',
    ClockFace.segment => '8-segment',
  };

  String get chineseName => switch (this) {
    ClockFace.analog => '模拟',
    ClockFace.flip => '翻页',
    ClockFace.binary => '二进制',
    ClockFace.big => '超大数字',
    ClockFace.segment => '8 段码',
  };
}

String clockFaceName(BuildContext context, ClockFace face) =>
    tr(context, face.englishName, face.chineseName);

({String hour, String minute, String second, String period}) clockDigitsFor(
  DateTime now, {
  required bool use24Hour,
}) {
  final hour24 = now.hour;
  final hour = use24Hour ? hour24 : (hour24 % 12 == 0 ? 12 : hour24 % 12);
  return (
    hour: hour.toString().padLeft(2, '0'),
    minute: now.minute.toString().padLeft(2, '0'),
    second: now.second.toString().padLeft(2, '0'),
    period: use24Hour ? '' : (hour24 < 12 ? 'AM' : 'PM'),
  );
}

List<int> clockBinaryDigits(DateTime now, {required bool use24Hour}) {
  final hour = use24Hour ? now.hour : (now.hour % 12 == 0 ? 12 : now.hour % 12);
  return [
    hour ~/ 10,
    hour % 10,
    now.minute ~/ 10,
    now.minute % 10,
    now.second ~/ 10,
    now.second % 10,
  ];
}

bool clockBinaryBit(int digit, int weight) => (digit & weight) != 0;

const int defaultSegmentColor = 0xff74f0df;

class ClockSettings {
  ClockSettings();

  bool loop = false;
  ClockLayout layout = ClockLayout.auto;
  ClockThemeMode theme = ClockThemeMode.app;
  int? accent;
  bool? use24Hour;
  double analogScale = 1;
  bool analogShowDigital = true;
  bool analogShowDate = true;
  bool analogShowMinuteHand = true;
  bool analogShowSecondHand = true;
  double flipScale = 1;
  bool flipShowSeconds = true;
  bool flipShowDate = true;
  double binaryScale = 1;
  bool binaryShowSeconds = true;
  bool binaryShowLabels = true;
  bool binaryShowDigital = true;
  bool binaryShowDate = true;
  bool bigShowDate = true;
  bool bigShowSeconds = true;
  double segmentScale = 1;
  bool segmentShowSeconds = true;
  bool segmentShowDate = true;
  int segmentColor = defaultSegmentColor;
  bool segmentShowBorder = true;
  double segmentBorderWidth = 1;
  double segmentPadding = 20;
  double segmentMargin = 0;

  void resetGeneral() {
    loop = false;
    layout = ClockLayout.auto;
    use24Hour = null;
  }

  void resetAppearance() {
    theme = ClockThemeMode.app;
    accent = null;
  }

  void resetAnalog() {
    analogScale = 1;
    analogShowDigital = true;
    analogShowDate = true;
    analogShowMinuteHand = true;
    analogShowSecondHand = true;
  }

  void resetFlip() {
    flipScale = 1;
    flipShowSeconds = true;
    flipShowDate = true;
  }

  void resetBinary() {
    binaryScale = 1;
    binaryShowSeconds = true;
    binaryShowLabels = true;
    binaryShowDigital = true;
    binaryShowDate = true;
  }

  void resetBig() {
    bigShowDate = true;
    bigShowSeconds = true;
  }

  void resetSegment() {
    segmentScale = 1;
    segmentShowSeconds = true;
    segmentShowDate = true;
    segmentColor = defaultSegmentColor;
    segmentShowBorder = true;
    segmentBorderWidth = 1;
    segmentPadding = 20;
    segmentMargin = 0;
  }

  void resetAll() {
    resetGeneral();
    resetAppearance();
    resetAnalog();
    resetFlip();
    resetBinary();
    resetBig();
    resetSegment();
  }

  Map<String, dynamic> toJson() => {
    'loop': loop,
    'layout': layout.name,
    'theme': theme.name,
    'accent': accent,
    'use24': use24Hour,
    'analogScale': analogScale,
    'analogDigital': analogShowDigital,
    'analogDate': analogShowDate,
    'analogMinuteHand': analogShowMinuteHand,
    'analogSecondHand': analogShowSecondHand,
    'flipScale': flipScale,
    'flipSeconds': flipShowSeconds,
    'flipDate': flipShowDate,
    'binaryScale': binaryScale,
    'binarySeconds': binaryShowSeconds,
    'binaryLabels': binaryShowLabels,
    'binaryDigital': binaryShowDigital,
    'binaryDate': binaryShowDate,
    'bigDate': bigShowDate,
    'bigSeconds': bigShowSeconds,
    'segmentScale': segmentScale,
    'segmentSeconds': segmentShowSeconds,
    'segmentDate': segmentShowDate,
    'segmentColor': segmentColor,
    'segmentBorder': segmentShowBorder,
    'segmentBorderWidth': segmentBorderWidth,
    'segmentPadding': segmentPadding,
    'segmentMargin': segmentMargin,
  };

  factory ClockSettings.fromJson(Map<String, dynamic> json) {
    final settings = ClockSettings();
    settings.loop = json['loop'] == true;
    settings.layout = switch (json['layout']) {
      'portrait' => ClockLayout.portrait,
      'landscape' => ClockLayout.landscape,
      _ => ClockLayout.auto,
    };
    settings.theme = switch (json['theme']) {
      'light' => ClockThemeMode.light,
      'dark' => ClockThemeMode.dark,
      _ => ClockThemeMode.app,
    };
    final accent = json['accent'];
    if (accent is num) {
      final value = accent.toInt();
      if (value >= 0 && value <= 0xffffffff) {
        settings.accent = value;
      }
    }
    final use24 = json['use24'];
    if (use24 is bool) settings.use24Hour = use24;
    settings.analogScale = _readScale(json['analogScale']);
    settings.analogShowDigital = _readBool(json['analogDigital'], true);
    settings.analogShowDate = _readBool(json['analogDate'], true);
    settings.analogShowMinuteHand = _readBool(json['analogMinuteHand'], true);
    settings.analogShowSecondHand = _readBool(json['analogSecondHand'], true);
    settings.flipScale = _readScale(json['flipScale']);
    settings.flipShowSeconds = _readBool(json['flipSeconds'], true);
    settings.flipShowDate = _readBool(json['flipDate'], true);
    settings.binaryScale = _readScale(json['binaryScale']);
    settings.binaryShowSeconds = _readBool(json['binarySeconds'], true);
    settings.binaryShowLabels = _readBool(json['binaryLabels'], true);
    settings.binaryShowDigital = _readBool(json['binaryDigital'], true);
    settings.binaryShowDate = _readBool(json['binaryDate'], true);
    settings.bigShowDate = _readBool(json['bigDate'], true);
    settings.bigShowSeconds = _readBool(json['bigSeconds'], true);
    settings.segmentScale = _readScale(json['segmentScale']);
    settings.segmentShowSeconds = _readBool(json['segmentSeconds'], true);
    settings.segmentShowDate = _readBool(json['segmentDate'], true);
    final segmentColor = json['segmentColor'];
    if (segmentColor is num) {
      final value = segmentColor.toInt();
      if (value >= 0 && value <= 0xffffffff) {
        settings.segmentColor = value;
      }
    }
    settings.segmentShowBorder = _readBool(json['segmentBorder'], true);
    settings.segmentBorderWidth = _readBorderWidth(json['segmentBorderWidth']);
    settings.segmentPadding = _readSegmentPadding(json['segmentPadding']);
    settings.segmentMargin = _readSegmentMargin(json['segmentMargin']);
    return settings;
  }

  static double _readScale(dynamic value) {
    if (value is num && value.isFinite) {
      return value.toDouble().clamp(0.7, 1.2).toDouble();
    }
    return 1;
  }

  static double _readBorderWidth(dynamic value) {
    if (value is num && value.isFinite) {
      return value.toDouble().clamp(0.5, 3.0).toDouble();
    }
    return 1;
  }

  static double _readSegmentPadding(dynamic value) {
    if (value is num && value.isFinite) {
      return value.toDouble().clamp(8.0, 48.0).toDouble();
    }
    return 20;
  }

  static double _readSegmentMargin(dynamic value) {
    if (value is num && value.isFinite) {
      return value.toDouble().clamp(0.0, 48.0).toDouble();
    }
    return 0;
  }

  static bool _readBool(dynamic value, bool fallback) =>
      value is bool ? value : fallback;
}

class ClockScreen extends StatefulWidget {
  const ClockScreen({
    super.key,
    this.initialFace = ClockFace.analog,
    this.preferences,
  });

  final ClockFace initialFace;
  final LocalPreferences? preferences;

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> with WidgetsBindingObserver {
  static const _faces = ClockFace.values;
  static const _loopBase = 4000;
  late PageController _pageController;
  late int _faceIndex;
  DateTime _now = DateTime.now();
  Timer? _tickTimer;
  Timer? _controlsTimer;
  bool _fullscreen = false;
  bool _desktopFullscreen = false;
  bool _controlsVisible = true;
  bool _keepAwake = true;
  bool _wakeLockUnavailable = false;
  bool _backgrounded = false;
  ClockSettings _settings = ClockSettings();
  late final LocalPreferences _preferences;
  bool _settingsTouched = false;
  Timer? _saveTimer;

  ClockFace get _face => _faces[_faceIndex];

  bool get _desktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  bool _resolveUse24Hour(BuildContext context) =>
      _settings.use24Hour ??
      (MediaQuery.of(context).alwaysUse24HourFormat ||
          Localizations.localeOf(context).languageCode == 'zh');

  bool _usePortrait(BuildContext context) => switch (_settings.layout) {
    ClockLayout.portrait => true,
    ClockLayout.landscape => false,
    ClockLayout.auto =>
      MediaQuery.of(context).orientation == Orientation.portrait,
  };

  ThemeData? _cachedClockTheme;
  (ClockThemeMode, int?, Brightness, Color)? _cachedClockThemeKey;

  ThemeData _clockTheme(BuildContext context) {
    final ambient = Theme.of(context);
    final mode = _settings.theme;
    final accent = _settings.accent;
    if (mode == ClockThemeMode.app && accent == null) return ambient;
    final brightness = switch (mode) {
      ClockThemeMode.app => ambient.brightness,
      ClockThemeMode.light => Brightness.light,
      ClockThemeMode.dark => Brightness.dark,
    };
    final seed = accent == null ? ambient.colorScheme.primary : Color(accent);
    final key = (mode, accent, brightness, seed);
    if (_cachedClockTheme != null && _cachedClockThemeKey == key) {
      return _cachedClockTheme!;
    }
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final theme = ThemeData(colorScheme: scheme, useMaterial3: true);
    _cachedClockTheme = theme;
    _cachedClockThemeKey = key;
    return theme;
  }

  @override
  void initState() {
    super.initState();
    _preferences =
        widget.preferences ?? LocalPreferences.forFile('tool_clock.json');
    _faceIndex = widget.initialFace.index;
    _pageController = PageController(
      initialPage: _settings.loop ? _loopBase + _faceIndex : _faceIndex,
    );
    WidgetsBinding.instance.addObserver(this);
    _scheduleTick();
    unawaited(_syncWakelock());
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    _controlsTimer?.cancel();
    _saveTimer?.cancel();
    if (_settingsTouched) unawaited(_saveSettings());
    if (_fullscreen) unawaited(_showSystemUi());
    if (_desktopFullscreen) {
      unawaited(_setDesktopFullscreen(false));
    }
    unawaited(WakelockPlus.disable().catchError((_) {}));
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
      setState(() => _now = DateTime.now());
      _scheduleTick();
      if (_fullscreen) unawaited(_hideSystemUi());
      unawaited(_syncWakelock());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
      _tickTimer?.cancel();
      _saveTimer?.cancel();
      if (_settingsTouched) unawaited(_saveSettings());
      unawaited(WakelockPlus.disable().catchError((_) {}));
    }
  }

  void _scheduleTick() {
    _tickTimer?.cancel();
    final now = DateTime.now();
    final delay = Duration(milliseconds: 1000 - now.millisecond);
    _tickTimer = Timer(delay, () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  Future<void> _loadSettings() async {
    final raw = await _preferences.getString('settings');
    if (!mounted || raw == null || _settingsTouched) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final loaded = ClockSettings.fromJson(Map<String, dynamic>.from(decoded));
      final loopChanged = loaded.loop != _settings.loop;
      setState(() => _settings = loaded);
      if (loopChanged) _resetPager();
    } catch (_) {
      // Keep the defaults when the stored data cannot be read.
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _preferences.setString('settings', jsonEncode(_settings.toJson()));
    } catch (_) {}
  }

  void _scheduleSave() {
    _settingsTouched = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 150), () {
      unawaited(_saveSettings());
    });
  }

  void _mutateSettings(VoidCallback update) {
    _settingsTouched = true;
    setState(update);
    _scheduleSave();
  }

  Future<void> _syncWakelock() async {
    if (_backgrounded) return;
    try {
      if (_keepAwake) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _wakeLockUnavailable = true;
        _keepAwake = false;
      });
    }
  }

  Future<void> _setKeepAwake(bool value) async {
    if (_wakeLockUnavailable) return;
    setState(() => _keepAwake = value);
    await _syncWakelock();
  }

  Future<void> _hideSystemUi() async {
    try {
      if (Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: const [],
        );
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    } catch (_) {}
  }

  Future<void> _showSystemUi() async {
    try {
      if (Platform.isIOS) {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    } catch (_) {}
  }

  Future<void> _setDesktopFullscreen(bool value) async {
    if (!_desktop) return;
    try {
      await windowManager.ensureInitialized();
      if (await windowManager.isFullScreen() != value) {
        await windowManager.setFullScreen(value);
      }
      _desktopFullscreen = value;
    } catch (_) {
      // Keep the in-app fullscreen layout if the window cannot change.
    }
  }

  Future<void> _setFullscreen(bool value) async {
    if (_fullscreen == value) return;
    _controlsTimer?.cancel();
    _controlsTimer = null;
    setState(() {
      _fullscreen = value;
      _controlsVisible = value;
    });
    if (value) {
      _showControlsTemporarily();
      await _hideSystemUi();
    } else {
      await _showSystemUi();
    }
    if (_desktop) {
      if (_fullscreen == value) await _setDesktopFullscreen(value);
    }
  }

  void _showControlsTemporarily() {
    _controlsTimer?.cancel();
    if (!_fullscreen) return;
    if (mounted) setState(() => _controlsVisible = true);
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    if (!_fullscreen) return;
    if (_controlsVisible) {
      _controlsTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControlsTemporarily();
    }
  }

  void _setLoop(bool value) {
    if (_settings.loop == value) return;
    _settings.loop = value;
    _resetPager();
    _scheduleSave();
  }

  void _resetPager() {
    final oldController = _pageController;
    final newController = PageController(
      initialPage: _settings.loop ? _loopBase + _faceIndex : _faceIndex,
    );
    setState(() => _pageController = newController);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => oldController.dispose(),
    );
  }

  void _goToFace(int index) {
    final target = index < 0
        ? 0
        : (index >= _faces.length ? _faces.length - 1 : index);
    if (_settings.loop) {
      final page = _pageController.hasClients && _pageController.page != null
          ? _pageController.page!.round()
          : _loopBase + _faceIndex;
      var delta = target - page % _faces.length;
      if (delta > _faces.length ~/ 2) delta -= _faces.length;
      if (delta < -(_faces.length ~/ 2)) delta += _faces.length;
      if (delta == 0) return;
      _pageController.animateToPage(
        page + delta,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (target == _faceIndex) return;
    setState(() => _faceIndex = target);
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _previousFace() {
    if (_settings.loop) {
      if (_pageController.hasClients) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    _goToFace(_faceIndex - 1);
  }

  void _nextFace() {
    if (_settings.loop) {
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    _goToFace(_faceIndex + 1);
  }

  Future<void> _openClockSettings() async {
    final sheetTheme = _clockTheme(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: sheetTheme.colorScheme.surfaceContainerLow,
      builder: (sheetContext) {
        return Theme(
          data: sheetTheme,
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              void refresh() => setSheetState(() {});
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 620,
                    maxHeight: MediaQuery.sizeOf(context).height * 0.84,
                  ),
                  child: _clockSettingsSheet(context, refresh),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _clockSettingsSheet(BuildContext context, VoidCallback refresh) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(
            children: [
              Text(
                tr(context, 'Clock settings', '时钟设置'),
                style: theme.textTheme.titleLarge,
              ),
              const Spacer(),
              IconButton(
                key: const ValueKey('clock-reset-all'),
                tooltip: tr(context, 'Reset all settings', '重置所有设置'),
                onPressed: () {
                  final loopBefore = _settings.loop;
                  _mutateSettings(_settings.resetAll);
                  if (loopBefore != _settings.loop) _resetPager();
                  refresh();
                },
                icon: const Icon(Icons.restart_alt),
              ),
              IconButton(
                key: const ValueKey('clock-settings-close'),
                tooltip: tr(context, 'Close', '关闭'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            key: const ValueKey('clock-settings-sheet'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _clockSettingsContent(context, refresh),
          ),
        ),
      ],
    );
  }

  Widget _clockSettingsContent(BuildContext context, VoidCallback refresh) {
    final theme = Theme.of(context);
    final use24Hour = _resolveUse24Hour(context);

    void apply(VoidCallback update) {
      _mutateSettings(update);
      refresh();
    }

    void resetSection(VoidCallback reset) {
      _mutateSettings(reset);
      refresh();
    }

    Widget section(
      IconData icon,
      String english,
      String chinese,
      List<Widget> children, {
      Key? resetKey,
      VoidCallback? onReset,
    }) => _settingsSection(
      context,
      icon,
      english,
      chinese,
      children,
      resetKey: resetKey,
      onReset: onReset,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section(Icons.tune, 'General', '通用', [
          SwitchListTile(
            key: const ValueKey('clock-loop'),
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, 'Loop between clocks', '循环滑动')),
            subtitle: Text(
              tr(
                context,
                'Swiping past the last clock wraps to the first.',
                '从最后一个表盘继续滑动会回到第一个。',
              ),
            ),
            value: _settings.loop,
            onChanged: (value) {
              _setLoop(value);
              refresh();
            },
          ),
          const SizedBox(height: 8),
          Text(
            tr(context, 'Hour format', '小时制'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            key: const ValueKey('clock-hour-format'),
            segments: [
              ButtonSegment(
                value: false,
                label: Text(tr(context, '12-hour', '12 小时')),
              ),
              ButtonSegment(
                value: true,
                label: Text(tr(context, '24-hour', '24 小时')),
              ),
            ],
            selected: {use24Hour},
            onSelectionChanged: (selection) {
              apply(() => _settings.use24Hour = selection.first);
            },
          ),
          const SizedBox(height: 4),
          Text(
            tr(
              context,
              'Follows your system setting until you choose one.',
              '未选择时跟随系统设置。',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(tr(context, 'Layout', '布局'), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          SegmentedButton<ClockLayout>(
            key: const ValueKey('clock-layout'),
            segments: [
              for (final layout in ClockLayout.values)
                ButtonSegment(
                  value: layout,
                  label: Text(
                    tr(context, layout.englishName, layout.chineseName),
                  ),
                ),
            ],
            selected: {_settings.layout},
            onSelectionChanged: (selection) {
              apply(() => _settings.layout = selection.first);
            },
          ),
        ]),
        const Divider(height: 32),
        section(
          Icons.access_time,
          'Analog',
          '模拟',
          [
            _sizeSlider(
              context,
              key: const ValueKey('clock-analog-scale'),
              value: _settings.analogScale,
              onChanged: (value) => apply(() => _settings.analogScale = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-analog-minute-hand'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Minute hand', '分针')),
              value: _settings.analogShowMinuteHand,
              onChanged: (value) =>
                  apply(() => _settings.analogShowMinuteHand = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-analog-second-hand'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Second hand', '秒针')),
              value: _settings.analogShowSecondHand,
              onChanged: (value) =>
                  apply(() => _settings.analogShowSecondHand = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-analog-digital'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Digital clock', '数字时钟')),
              subtitle: Text(
                tr(
                  context,
                  'Show the digital time below the face.',
                  '在表盘下方显示数字时间。',
                ),
              ),
              value: _settings.analogShowDigital,
              onChanged: (value) =>
                  apply(() => _settings.analogShowDigital = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-analog-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Date', '日期')),
              value: _settings.analogShowDate,
              onChanged: (value) =>
                  apply(() => _settings.analogShowDate = value),
            ),
          ],
          resetKey: const ValueKey('clock-reset-analog'),
          onReset: () => resetSection(_settings.resetAnalog),
        ),
        const Divider(height: 32),
        section(
          Icons.flip_to_front_outlined,
          'Flip',
          '翻页',
          [
            _sizeSlider(
              context,
              key: const ValueKey('clock-flip-scale'),
              value: _settings.flipScale,
              onChanged: (value) => apply(() => _settings.flipScale = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-flip-seconds'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Seconds', '秒数')),
              value: _settings.flipShowSeconds,
              onChanged: (value) =>
                  apply(() => _settings.flipShowSeconds = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-flip-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Calendar date', '日历日期')),
              value: _settings.flipShowDate,
              onChanged: (value) => apply(() => _settings.flipShowDate = value),
            ),
          ],
          resetKey: const ValueKey('clock-reset-flip'),
          onReset: () => resetSection(_settings.resetFlip),
        ),
        const Divider(height: 32),
        section(
          Icons.grid_on,
          'Binary',
          '二进制',
          [
            _sizeSlider(
              context,
              key: const ValueKey('clock-binary-scale'),
              value: _settings.binaryScale,
              onChanged: (value) => apply(() => _settings.binaryScale = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-binary-seconds'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Seconds', '秒数')),
              subtitle: Text(
                tr(
                  context,
                  'Show seconds in the columns and digital time.',
                  '在点阵和数字时间中显示秒数。',
                ),
              ),
              value: _settings.binaryShowSeconds,
              onChanged: (value) =>
                  apply(() => _settings.binaryShowSeconds = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-binary-labels'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Labels', '标签')),
              subtitle: Text(
                tr(
                  context,
                  'Show the title, 8/4/2/1 legend, and column digits.',
                  '显示标题、8/4/2/1 图例和列数字。',
                ),
              ),
              value: _settings.binaryShowLabels,
              onChanged: (value) =>
                  apply(() => _settings.binaryShowLabels = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-binary-digital'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Digital clock', '数字时钟')),
              subtitle: Text(
                tr(
                  context,
                  'Show the decimal time under the dots.',
                  '在点阵下方显示十进制时间。',
                ),
              ),
              value: _settings.binaryShowDigital,
              onChanged: (value) =>
                  apply(() => _settings.binaryShowDigital = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-binary-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Date', '日期')),
              value: _settings.binaryShowDate,
              onChanged: (value) =>
                  apply(() => _settings.binaryShowDate = value),
            ),
          ],
          resetKey: const ValueKey('clock-reset-binary'),
          onReset: () => resetSection(_settings.resetBinary),
        ),
        const Divider(height: 32),
        section(
          Icons.text_fields,
          'Big digits',
          '超大数字',
          [
            SwitchListTile(
              key: const ValueKey('clock-big-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Date', '日期')),
              value: _settings.bigShowDate,
              onChanged: (value) => apply(() => _settings.bigShowDate = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-big-seconds'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Seconds', '秒数')),
              value: _settings.bigShowSeconds,
              onChanged: (value) =>
                  apply(() => _settings.bigShowSeconds = value),
            ),
          ],
          resetKey: const ValueKey('clock-reset-big'),
          onReset: () => resetSection(_settings.resetBig),
        ),
        const Divider(height: 32),
        section(
          Icons.dialpad,
          '8-segment',
          '8 段码',
          [
            _sizeSlider(
              context,
              key: const ValueKey('clock-segment-scale'),
              value: _settings.segmentScale,
              onChanged: (value) => apply(() => _settings.segmentScale = value),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr(context, 'Color', '颜色'),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var index = 0; index < segmentColorOptions.length; index++)
                  _SegmentColorSwatch(
                    key: ValueKey('clock-segment-color-$index'),
                    color: segmentColorOptions[index],
                    selected:
                        _settings.segmentColor ==
                        segmentColorOptions[index].toARGB32(),
                    onTap: () => apply(
                      () => _settings.segmentColor = segmentColorOptions[index]
                          .toARGB32(),
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              key: const ValueKey('clock-segment-border'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Border', '边框')),
              value: _settings.segmentShowBorder,
              onChanged: (value) =>
                  apply(() => _settings.segmentShowBorder = value),
            ),
            if (_settings.segmentShowBorder)
              _borderWidthSlider(
                context,
                key: const ValueKey('clock-segment-border-width'),
                value: _settings.segmentBorderWidth,
                onChanged: (value) =>
                    apply(() => _settings.segmentBorderWidth = value),
              ),
            _spacingSlider(
              context,
              key: const ValueKey('clock-segment-padding'),
              english: 'Padding',
              chinese: '内边距',
              value: _settings.segmentPadding,
              min: 8,
              max: 48,
              divisions: 20,
              onChanged: (value) =>
                  apply(() => _settings.segmentPadding = value),
            ),
            _spacingSlider(
              context,
              key: const ValueKey('clock-segment-margin'),
              english: 'Margin',
              chinese: '外边距',
              value: _settings.segmentMargin,
              min: 0,
              max: 48,
              divisions: 12,
              onChanged: (value) =>
                  apply(() => _settings.segmentMargin = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-segment-seconds'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Seconds', '秒数')),
              value: _settings.segmentShowSeconds,
              onChanged: (value) =>
                  apply(() => _settings.segmentShowSeconds = value),
            ),
            SwitchListTile(
              key: const ValueKey('clock-segment-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Date', '日期')),
              value: _settings.segmentShowDate,
              onChanged: (value) =>
                  apply(() => _settings.segmentShowDate = value),
            ),
          ],
          resetKey: const ValueKey('clock-reset-segment'),
          onReset: () => resetSection(_settings.resetSegment),
        ),
      ],
    );
  }

  Widget _settingsSection(
    BuildContext context,
    IconData icon,
    String english,
    String chinese,
    List<Widget> children, {
    Key? resetKey,
    VoidCallback? onReset,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(context, english, chinese),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (onReset != null)
              IconButton(
                key: resetKey,
                tooltip: tr(context, 'Reset $english settings', '重置$chinese设置'),
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt),
              ),
          ],
        ),
        ...children,
      ],
    );
  }

  Widget _sizeSlider(
    BuildContext context, {
    required Key key,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              tr(context, 'Size', '尺寸'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Slider(
              key: key,
              value: value,
              min: 0.7,
              max: 1.2,
              divisions: 10,
              label: '${(value * 100).round()}%',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _spacingSlider(
    BuildContext context, {
    required Key key,
    required String english,
    required String chinese,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              tr(context, english, chinese),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Slider(
              key: key,
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: '${value.round()} px',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${value.round()} px',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _borderWidthSlider(
    BuildContext context, {
    required Key key,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              tr(context, 'Border width', '边框宽度'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Slider(
              key: key,
              value: value,
              min: 0.5,
              max: 3,
              divisions: 5,
              label: '${value.toStringAsFixed(1)} px',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${value.toStringAsFixed(1)} px',
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _wakelockButton(BuildContext context, {required Key buttonKey}) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: buttonKey,
      tooltip: _wakeLockUnavailable
          ? tr(context, 'Keep screen on: unavailable', '屏幕常亮：不可用')
          : _keepAwake
          ? tr(context, 'Keep screen on: on', '屏幕常亮：开')
          : tr(context, 'Keep screen on: off', '屏幕常亮：关'),
      isSelected: _keepAwake,
      onPressed: _wakeLockUnavailable ? null : () => _setKeepAwake(!_keepAwake),
      icon: Icon(
        _keepAwake ? Icons.desktop_windows : Icons.desktop_windows_outlined,
        color: _wakeLockUnavailable
            ? null
            : _keepAwake
            ? scheme.primary
            : scheme.onSurfaceVariant,
      ),
    );
  }

  Widget _appearanceButton(BuildContext context, {required Key buttonKey}) {
    final scheme = Theme.of(context).colorScheme;
    final custom =
        _settings.theme != ClockThemeMode.app || _settings.accent != null;
    return IconButton(
      key: buttonKey,
      tooltip: tr(context, 'Clock appearance', '时钟外观'),
      onPressed: _openClockAppearance,
      icon: Icon(Icons.palette_outlined, color: custom ? scheme.primary : null),
    );
  }

  Future<void> _openClockAppearance() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void refresh() => setSheetState(() {});
            final theme = _clockTheme(context);
            return Theme(
              data: theme,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Material(
                    key: const ValueKey('clock-theme-sheet'),
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _clockAppearanceContent(context, refresh),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _clockAppearanceContent(BuildContext context, VoidCallback refresh) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    void apply(VoidCallback update) {
      _mutateSettings(update);
      refresh();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.palette_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(context, 'Clock appearance', '时钟外观'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: const ValueKey('clock-theme-reset'),
                tooltip: tr(context, 'Reset appearance', '重置外观'),
                onPressed: () => apply(_settings.resetAppearance),
                icon: const Icon(Icons.restart_alt),
              ),
              IconButton(
                key: const ValueKey('clock-theme-close'),
                tooltip: tr(context, 'Close', '关闭'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            tr(
              context,
              'Theme and accent color apply to this clock only.',
              '主题和强调色仅作用于时钟界面。',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(tr(context, 'Theme', '主题'), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          SegmentedButton<ClockThemeMode>(
            key: const ValueKey('clock-theme-mode'),
            segments: [
              for (final mode in ClockThemeMode.values)
                ButtonSegment(
                  value: mode,
                  icon: Icon(switch (mode) {
                    ClockThemeMode.app => Icons.auto_mode,
                    ClockThemeMode.light => Icons.light_mode_outlined,
                    ClockThemeMode.dark => Icons.dark_mode_outlined,
                  }),
                  label: Text(tr(context, mode.englishName, mode.chineseName)),
                ),
            ],
            selected: {_settings.theme},
            onSelectionChanged: (selection) {
              apply(() => _settings.theme = selection.first);
            },
          ),
          const SizedBox(height: 18),
          Text(
            tr(context, 'Accent color', '强调色'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _clockAccentSwatch(context, null, refresh),
              for (final preset in clockAccentPresets)
                _clockAccentSwatch(context, preset, refresh),
            ],
          ),
        ],
      ),
    );
  }

  Widget _clockAccentSwatch(
    BuildContext context,
    ClockAccentPreset? preset,
    VoidCallback refresh,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _settings.accent == preset?.color;
    final color = preset == null ? scheme.primary : Color(preset.color);
    final label = preset == null
        ? tr(context, 'Follow app color', '跟随应用颜色')
        : tr(context, preset.englishName, preset.chineseName);
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          key: ValueKey(
            preset == null ? 'clock-accent-auto' : 'clock-accent-${preset.id}',
          ),
          customBorder: const CircleBorder(),
          onTap: () {
            _mutateSettings(() => _settings.accent = preset?.color);
            refresh();
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: preset == null
                ? Icon(Icons.auto_mode, size: 18, color: foreground)
                : selected
                ? Icon(Icons.check, size: 18, color: foreground)
                : null,
          ),
        ),
      ),
    );
  }

  Widget _faceSwitcher(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dots = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < _faces.length; index++)
          Semantics(
            button: true,
            selected: index == _faceIndex,
            label: clockFaceName(context, _faces[index]),
            child: GestureDetector(
              key: ValueKey('clock-dot-$index'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _goToFace(index),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: index == _faceIndex ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: index == _faceIndex
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    final center = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(clockFaceName(context, _face), style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        dots,
      ],
    );
    final previous = IconButton(
      tooltip: tr(context, 'Previous clock', '上一个时钟'),
      onPressed: _settings.loop || _faceIndex > 0 ? _previousFace : null,
      icon: const Icon(Icons.chevron_left),
    );
    final next = IconButton(
      tooltip: tr(context, 'Next clock', '下一个时钟'),
      onPressed: _settings.loop || _faceIndex < _faces.length - 1
          ? _nextFace
          : null,
      icon: const Icon(Icons.chevron_right),
    );
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [previous, center, next],
      );
    }
    return Row(
      children: [
        previous,
        Expanded(child: center),
        next,
      ],
    );
  }

  Widget _bottomBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: _faceSwitcher(context, compact: false),
        ),
      ),
    );
  }

  Widget _fullscreenOverlay(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !_controlsVisible,
      child: AnimatedOpacity(
        opacity: _controlsVisible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: Stack(
          children: [
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: Material(
                  color: scheme.surfaceContainer.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(28),
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _appearanceButton(
                        context,
                        buttonKey: const ValueKey('clock-theme-overlay'),
                      ),
                      _wakelockButton(
                        context,
                        buttonKey: const ValueKey('clock-wakelock-overlay'),
                      ),
                      IconButton(
                        key: const ValueKey('clock-settings-overlay'),
                        tooltip: tr(context, 'Clock settings', '时钟设置'),
                        onPressed: _openClockSettings,
                        icon: const Icon(Icons.tune),
                      ),
                      IconButton(
                        key: const ValueKey('clock-exit-fullscreen'),
                        tooltip: tr(context, 'Exit fullscreen', '退出全屏'),
                        onPressed: () => _setFullscreen(false),
                        icon: const Icon(Icons.fullscreen_exit),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: Center(
                  child: Material(
                    color: scheme.surfaceContainer.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(28),
                    elevation: 2,
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _faceSwitcher(context, compact: true),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFace(ClockFace face, bool use24Hour, bool portrait) {
    return _ClockPageBackground(
      child: KeyedSubtree(
        key: ValueKey(
          'clock-layout-${face.name}-${portrait ? 'portrait' : 'landscape'}',
        ),
        child: switch (face) {
          ClockFace.analog => _AnalogClockPage(
            now: _now,
            use24Hour: use24Hour,
            portrait: portrait,
            scale: _settings.analogScale,
            showDigital: _settings.analogShowDigital,
            showDate: _settings.analogShowDate,
            showMinuteHand: _settings.analogShowMinuteHand,
            showSecondHand: _settings.analogShowSecondHand,
          ),
          ClockFace.flip => _FlipClockPage(
            now: _now,
            use24Hour: use24Hour,
            portrait: portrait,
            scale: _settings.flipScale,
            showSeconds: _settings.flipShowSeconds,
            showDate: _settings.flipShowDate,
          ),
          ClockFace.binary => _BinaryClockPage(
            now: _now,
            use24Hour: use24Hour,
            portrait: portrait,
            scale: _settings.binaryScale,
            showSeconds: _settings.binaryShowSeconds,
            showLabels: _settings.binaryShowLabels,
            showDigital: _settings.binaryShowDigital,
            showDate: _settings.binaryShowDate,
          ),
          ClockFace.big => _BigDigitsClockPage(
            now: _now,
            use24Hour: use24Hour,
            portrait: portrait,
            showDate: _settings.bigShowDate,
            showSeconds: _settings.bigShowSeconds,
          ),
          ClockFace.segment => _SegmentClockPage(
            now: _now,
            use24Hour: use24Hour,
            portrait: portrait,
            scale: _settings.segmentScale,
            showSeconds: _settings.segmentShowSeconds,
            showDate: _settings.segmentShowDate,
            color: Color(_settings.segmentColor),
            showBorder: _settings.segmentShowBorder,
            borderWidth: _settings.segmentBorderWidth,
            padding: _settings.segmentPadding,
            margin: _settings.segmentMargin,
          ),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final use24Hour = _resolveUse24Hour(context);
    final portrait = _usePortrait(context);
    final clockTheme = _clockTheme(context);
    return Theme(
      data: clockTheme,
      child: Builder(
        builder: (context) {
          final pages = PageView.builder(
            key: ValueKey('clock-pages-${_settings.loop ? 'loop' : 'finite'}'),
            controller: _pageController,
            itemCount: _settings.loop ? null : _faces.length,
            onPageChanged: (page) {
              final index = _settings.loop ? page % _faces.length : page;
              if (index != _faceIndex) setState(() => _faceIndex = index);
            },
            itemBuilder: (context, page) {
              final face = _faces[_settings.loop ? page % _faces.length : page];
              return _buildFace(face, use24Hour, portrait);
            },
          );
          final body = _fullscreen
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleControls,
                        child: pages,
                      ),
                    ),
                    _fullscreenOverlay(context),
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: pages),
                    _bottomBar(context),
                  ],
                );
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (_fullscreen) _setFullscreen(false);
              },
              const SingleActivator(LogicalKeyboardKey.keyF): () =>
                  _setFullscreen(!_fullscreen),
              const SingleActivator(LogicalKeyboardKey.arrowLeft):
                  _previousFace,
              const SingleActivator(LogicalKeyboardKey.arrowRight): _nextFace,
            },
            child: Focus(
              autofocus: true,
              child: PopScope(
                canPop: !_fullscreen,
                onPopInvokedWithResult: (didPop, result) {
                  if (!didPop && _fullscreen) _setFullscreen(false);
                },
                child: Scaffold(
                  appBar: _fullscreen
                      ? null
                      : AppBar(
                          title: Text(tr(context, 'Clock', '时钟')),
                          actions: [
                            _appearanceButton(
                              context,
                              buttonKey: const ValueKey('clock-theme'),
                            ),
                            _wakelockButton(
                              context,
                              buttonKey: const ValueKey('clock-wakelock'),
                            ),
                            IconButton(
                              key: const ValueKey('clock-settings'),
                              tooltip: tr(context, 'Clock settings', '时钟设置'),
                              onPressed: _openClockSettings,
                              icon: const Icon(Icons.tune),
                            ),
                            IconButton(
                              key: const ValueKey('clock-fullscreen'),
                              tooltip: tr(context, 'Fullscreen', '全屏'),
                              onPressed: () => _setFullscreen(true),
                              icon: const Icon(Icons.fullscreen),
                            ),
                            toolInfoAction(context, 'clock'),
                          ],
                        ),
                  body: body,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ClockPageBackground extends StatelessWidget {
  const _ClockPageBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.surface, scheme.surfaceContainerLow],
        ),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: child,
      ),
    );
  }
}

class _AnalogClockPage extends StatelessWidget {
  const _AnalogClockPage({
    required this.now,
    required this.use24Hour,
    required this.portrait,
    required this.scale,
    required this.showDigital,
    required this.showDate,
    required this.showMinuteHand,
    required this.showSecondHand,
  });

  final DateTime now;
  final bool use24Hour;
  final bool portrait;
  final double scale;
  final bool showDigital;
  final bool showDate;
  final bool showMinuteHand;
  final bool showSecondHand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final digits = clockDigitsFor(now, use24Hour: use24Hour);
    final date = MaterialLocalizations.of(context).formatMediumDate(now);
    final digital =
        '${digits.hour}:${digits.minute}:${digits.second}'
        '${digits.period.isNotEmpty ? ' ${digits.period}' : ''}';

    Widget face(double size) => SizedBox(
      key: const ValueKey('analog-face'),
      width: size,
      height: size,
      child: CustomPaint(
        key: ValueKey(
          'analog-hands-'
          '${showMinuteHand ? 1 : 0}${showSecondHand ? 1 : 0}',
        ),
        painter: _AnalogClockPainter(
          now: now,
          showMinuteHand: showMinuteHand,
          showSecondHand: showSecondHand,
          faceColor: scheme.surfaceContainerHigh,
          rimColor: scheme.outlineVariant,
          tickColor: scheme.onSurfaceVariant,
          numberColor: scheme.onSurfaceVariant,
          hourColor: scheme.onSurface,
          minuteColor: scheme.onSurface,
          secondColor: scheme.primary,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!portrait && (showDigital || showDate)) {
          final fit = max(
            60.0,
            min(constraints.maxWidth * 0.44, constraints.maxHeight - 24),
          );
          final faceSize = (fit * 0.9 * scale).clamp(60.0, fit);
          return Row(
            children: [
              Expanded(child: Center(child: face(faceSize))),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showDigital)
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            digital,
                            key: const ValueKey('analog-digital'),
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      if (showDate)
                        Padding(
                          padding: EdgeInsets.only(top: showDigital ? 8 : 0),
                          child: Text(
                            date,
                            key: const ValueKey('analog-date'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        final reserve =
            24.0 + (showDigital ? 30.0 : 0.0) + (showDate ? 24.0 : 0.0);
        final fit = max(
          60.0,
          min(constraints.maxWidth, constraints.maxHeight - reserve),
        );
        final faceSize = (fit * 0.88 * scale).clamp(60.0, fit);
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              face(faceSize),
              if (showDigital || showDate) const SizedBox(height: 16),
              if (showDigital)
                Text(
                  digital,
                  key: const ValueKey('analog-digital'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              if (showDate)
                Padding(
                  padding: EdgeInsets.only(top: showDigital ? 4 : 0),
                  child: Text(
                    date,
                    key: const ValueKey('analog-date'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AnalogClockPainter extends CustomPainter {
  _AnalogClockPainter({
    required this.now,
    required this.showMinuteHand,
    required this.showSecondHand,
    required this.faceColor,
    required this.rimColor,
    required this.tickColor,
    required this.numberColor,
    required this.hourColor,
    required this.minuteColor,
    required this.secondColor,
  });

  final DateTime now;
  final bool showMinuteHand;
  final bool showSecondHand;
  final Color faceColor;
  final Color rimColor;
  final Color tickColor;
  final Color numberColor;
  final Color hourColor;
  final Color minuteColor;
  final Color secondColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = min(size.width, size.height) / 2 - 4;
    if (radius <= 0) return;

    canvas.drawCircle(
      center,
      radius + 4,
      Paint()
        ..color = const Color(0x22000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(center, radius, Paint()..color = faceColor);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1, radius * 0.012)
        ..color = rimColor,
    );

    for (var tick = 0; tick < 60; tick++) {
      final angle = tick * pi / 30 - pi / 2;
      final isHourTick = tick % 5 == 0;
      final direction = Offset(cos(angle), sin(angle));
      final outer = center + direction * (radius - radius * 0.03);
      final inner =
          center + direction * (radius - radius * (isHourTick ? 0.12 : 0.07));
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = isHourTick ? tickColor : tickColor.withValues(alpha: 0.5)
          ..strokeWidth = isHourTick
              ? max(1.5, radius * 0.018)
              : max(1, radius * 0.007)
          ..strokeCap = StrokeCap.round,
      );
    }

    for (final marker in const [
      (label: '12', angle: -pi / 2),
      (label: '3', angle: 0.0),
      (label: '6', angle: pi / 2),
      (label: '9', angle: pi),
    ]) {
      final painter = TextPainter(
        text: TextSpan(
          text: marker.label,
          style: TextStyle(
            color: numberColor,
            fontSize: radius * 0.13,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final position =
          center +
          Offset(cos(marker.angle), sin(marker.angle)) * (radius * 0.77) -
          Offset(painter.width / 2, painter.height / 2);
      painter.paint(canvas, position);
    }

    final hourAngle =
        ((now.hour % 12) + now.minute / 60 + now.second / 3600) * pi / 6 -
        pi / 2;
    final minuteAngle = (now.minute + now.second / 60) * pi / 30 - pi / 2;
    final secondAngle = now.second * pi / 30 - pi / 2;

    _drawHand(
      canvas,
      center,
      hourAngle,
      radius * 0.47,
      max(3, radius * 0.035),
      hourColor,
    );
    if (showMinuteHand) {
      _drawHand(
        canvas,
        center,
        minuteAngle,
        radius * 0.68,
        max(2, radius * 0.024),
        minuteColor,
      );
    }
    if (showSecondHand) {
      _drawHand(
        canvas,
        center,
        secondAngle,
        radius * 0.78,
        max(1.4, radius * 0.012),
        secondColor,
        tail: radius * 0.12,
      );
      final tip =
          center + Offset(cos(secondAngle), sin(secondAngle)) * (radius * 0.78);
      canvas.drawCircle(
        tip,
        max(2, radius * 0.025),
        Paint()..color = secondColor,
      );
    }
    canvas.drawCircle(
      center,
      max(3, radius * 0.035),
      Paint()..color = secondColor,
    );
    canvas.drawCircle(
      center,
      max(1.5, radius * 0.016),
      Paint()..color = faceColor,
    );
  }

  void _drawHand(
    Canvas canvas,
    Offset center,
    double angle,
    double length,
    double width,
    Color color, {
    double tail = 0,
  }) {
    final direction = Offset(cos(angle), sin(angle));
    final start = center - direction * tail;
    final end = center + direction * length;
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_AnalogClockPainter oldDelegate) =>
      oldDelegate.now != now ||
      oldDelegate.showMinuteHand != showMinuteHand ||
      oldDelegate.showSecondHand != showSecondHand ||
      oldDelegate.faceColor != faceColor ||
      oldDelegate.rimColor != rimColor ||
      oldDelegate.tickColor != tickColor ||
      oldDelegate.numberColor != numberColor ||
      oldDelegate.hourColor != hourColor ||
      oldDelegate.minuteColor != minuteColor ||
      oldDelegate.secondColor != secondColor;
}

class _FlipClockPage extends StatelessWidget {
  const _FlipClockPage({
    required this.now,
    required this.use24Hour,
    required this.portrait,
    required this.scale,
    required this.showSeconds,
    required this.showDate,
  });

  final DateTime now;
  final bool use24Hour;
  final bool portrait;
  final double scale;
  final bool showSeconds;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final digits = clockDigitsFor(now, use24Hour: use24Hour);
    final date = MaterialLocalizations.of(context).formatMediumDate(now);
    return LayoutBuilder(
      builder: (context, constraints) {
        final reserve =
            28.0 +
            (showSeconds ? 24.0 : 0.0) +
            (showDate ? 24.0 : 0.0) +
            (digits.period.isNotEmpty ? 24.0 : 0.0);
        final double cardWidth;
        if (portrait) {
          final maxCardByWidth = (constraints.maxWidth - 48) / 2.08;
          final maxCardByHeight = (constraints.maxHeight - reserve - 60) / 2.87;
          final fit = max(24.0, min(maxCardByWidth, maxCardByHeight));
          final base = min(
            (constraints.maxWidth - 32) / 2.4,
            constraints.maxHeight * 0.22,
          );
          cardWidth = (base * scale).clamp(24.0, fit);
        } else {
          final maxCardByWidth = (constraints.maxWidth - 40) / 4.18;
          final maxCardByHeight = (constraints.maxHeight - reserve) / 1.36;
          final fit = max(24.0, min(maxCardByWidth, maxCardByHeight));
          final base = min(
            (constraints.maxWidth - 32) / 4.8,
            constraints.maxHeight * 0.28,
          );
          cardWidth = (base * scale).clamp(24.0, fit);
        }
        final cardHeight = cardWidth * 1.36;
        final colonSize = cardHeight * (portrait ? 0.34 : 0.42);
        final cardColor = scheme.surfaceContainerHighest;
        final dividerColor = scheme.outlineVariant;

        Widget card(String value) => _FlipCard(
          digit: value,
          width: cardWidth,
          height: cardHeight,
          background: cardColor,
          foreground: scheme.onSurface,
          divider: dividerColor,
        );

        Widget colon({required bool horizontal}) => horizontal
            ? SizedBox(
                width: cardWidth * 0.18,
                child: Center(
                  child: Opacity(
                    opacity: now.second.isEven ? 1 : 0.25,
                    child: Text(
                      ':',
                      style: TextStyle(
                        fontSize: colonSize,
                        height: 1,
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
            : SizedBox(
                height: cardHeight * 0.22,
                child: Center(
                  child: Opacity(
                    opacity: now.second.isEven ? 1 : 0.25,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: cardHeight * 0.045,
                          height: cardHeight * 0.045,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(height: cardHeight * 0.05),
                        Container(
                          width: cardHeight * 0.045,
                          height: cardHeight * 0.045,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );

        Widget cards() {
          if (portrait) {
            return Column(
              key: const ValueKey('flip-cards'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    card(digits.hour[0]),
                    const SizedBox(width: 8),
                    card(digits.hour[1]),
                  ],
                ),
                colon(horizontal: false),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    card(digits.minute[0]),
                    const SizedBox(width: 8),
                    card(digits.minute[1]),
                  ],
                ),
              ],
            );
          }
          return Row(
            key: const ValueKey('flip-cards'),
            mainAxisSize: MainAxisSize.min,
            children: [
              card(digits.hour[0]),
              const SizedBox(width: 8),
              card(digits.hour[1]),
              colon(horizontal: true),
              card(digits.minute[0]),
              const SizedBox(width: 8),
              card(digits.minute[1]),
            ],
          );
        }

        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                cards(),
                if (showSeconds || showDate || digits.period.isNotEmpty)
                  const SizedBox(height: 18),
                if (showSeconds)
                  Text(
                    '${digits.second} s',
                    key: const ValueKey('flip-seconds'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                if (showDate)
                  Padding(
                    padding: EdgeInsets.only(top: showSeconds ? 4 : 0),
                    child: Text(
                      date,
                      key: const ValueKey('flip-date'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (digits.period.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    digits.period,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FlipCard extends StatelessWidget {
  const _FlipCard({
    required this.digit,
    required this.width,
    required this.height,
    required this.background,
    required this.foreground,
    required this.divider,
  });

  final String digit;
  final double width;
  final double height;
  final Color background;
  final Color foreground;
  final Color divider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(width * 0.16),
        border: Border.all(color: divider.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final rotate = Tween<double>(
                  begin: -pi / 2,
                  end: 0,
                ).animate(animation);
                return AnimatedBuilder(
                  animation: rotate,
                  builder: (context, _) => Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0015)
                      ..rotateX(rotate.value),
                    child: Opacity(opacity: animation.value, child: child),
                  ),
                );
              },
              child: Padding(
                key: ValueKey(digit),
                padding: EdgeInsets.only(bottom: height * 0.02),
                child: Text(
                  digit,
                  style: TextStyle(
                    fontSize: height * 0.66,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: width * 0.08,
            right: width * 0.08,
            top: height / 2 - 0.5,
            child: Container(height: 1, color: divider.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

class _BinaryClockPage extends StatelessWidget {
  const _BinaryClockPage({
    required this.now,
    required this.use24Hour,
    required this.portrait,
    required this.scale,
    required this.showSeconds,
    required this.showLabels,
    required this.showDigital,
    required this.showDate,
  });

  final DateTime now;
  final bool use24Hour;
  final bool portrait;
  final double scale;
  final bool showSeconds;
  final bool showLabels;
  final bool showDigital;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final digits = clockBinaryDigits(now, use24Hour: use24Hour);
    final clock = clockDigitsFor(now, use24Hour: use24Hour);
    final date = MaterialLocalizations.of(context).formatMediumDate(now);
    const weights = [8, 4, 2, 1];

    return LayoutBuilder(
      builder: (context, constraints) {
        final double unit;
        if (portrait) {
          final rowCount = showSeconds ? 2 : 1;
          final reserve =
              24.0 +
              (showLabels ? 40.0 : 0.0) +
              (showDigital ? 52.0 : 0.0) +
              (showDate ? 24.0 : 0.0) +
              (showSeconds ? 40.0 : 0.0);
          final maxUnitByHeight = max(
            10.0,
            (constraints.maxHeight - reserve) / (5.65 * rowCount),
          );
          final maxUnitByWidth =
              constraints.maxWidth / (showLabels ? 8.6 : 6.8);
          final fit = max(10.0, min(maxUnitByWidth, maxUnitByHeight));
          final upper = max(10.0, fit);
          unit = (fit * 0.85 * scale).clamp(10.0, upper);
        } else {
          final columnCount = showSeconds ? 6 : 4;
          final separatorCount = showSeconds ? 2 : 1;
          final legendUnits = showLabels ? 1.78 : 0.0;
          final widthUnits =
              columnCount +
              (columnCount - 1) * 0.55 +
              separatorCount * 1.4 * 0.55 +
              legendUnits;
          final maxUnitByWidth = constraints.maxWidth / (widthUnits + 0.4);
          final reserve =
              24.0 +
              (showLabels ? 40.0 : 0.0) +
              (showDigital ? 52.0 : 0.0) +
              (showDate ? 24.0 : 0.0);
          final maxUnitByHeight = max(
            10.0,
            (constraints.maxHeight - reserve) / 5.65,
          );
          final fit = max(10.0, min(maxUnitByWidth, maxUnitByHeight));
          final upper = max(10.0, fit);
          unit = (fit * 0.85 * scale).clamp(10.0, upper);
        }
        final gap = unit * 0.55;

        Widget digitColumn(int index) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row < 4; row++) ...[
              _BinaryDot(
                on: clockBinaryBit(digits[index], weights[row]),
                size: unit,
                activeColor: scheme.primary,
                inactiveColor: scheme.onSurface.withValues(alpha: 0.08),
                borderColor: scheme.outlineVariant,
              ),
              if (row < 3) SizedBox(height: gap),
            ],
            if (showLabels) ...[
              const SizedBox(height: 8),
              Text(
                '${digits[index]}',
                key: ValueKey('binary-label-$index'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        );

        Widget separator() => SizedBox(
          width: gap * 1.4,
          height: unit * 4 + gap * 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: unit * 0.22,
                height: unit * 0.22,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(height: unit * 0.4),
              Container(
                width: unit * 0.22,
                height: unit * 0.22,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );

        Widget legend() => Column(
          key: const ValueKey('binary-legend'),
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var row = 0; row < 4; row++) ...[
              SizedBox(
                width: unit * 0.9,
                height: unit,
                child: Center(
                  child: Text(
                    '${weights[row]}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (row < 3) SizedBox(height: gap),
            ],
          ],
        );

        Widget title() => Text(
          tr(context, 'BINARY', '二进制'),
          key: const ValueKey('binary-label-title'),
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.primary,
            letterSpacing: 4,
            fontWeight: FontWeight.w600,
          ),
        );

        Widget footer() => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDigital || showDate) const SizedBox(height: 22),
            if (showDigital)
              Text(
                '${clock.hour}:${clock.minute}'
                '${showSeconds ? ':${clock.second}' : ''}'
                '${clock.period.isNotEmpty ? ' ${clock.period}' : ''}',
                key: const ValueKey('binary-digital'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            if (showDate)
              Padding(
                padding: EdgeInsets.only(top: showDigital ? 4 : 0),
                child: Text(
                  date,
                  key: const ValueKey('binary-date'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );

        if (portrait) {
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showLabels) ...[title(), const SizedBox(height: 18)],
                  Column(
                    key: const ValueKey('binary-matrix'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showLabels) ...[
                            legend(),
                            SizedBox(width: gap * 1.6),
                          ],
                          digitColumn(0),
                          SizedBox(width: gap),
                          digitColumn(1),
                          separator(),
                          digitColumn(2),
                          SizedBox(width: gap),
                          digitColumn(3),
                        ],
                      ),
                      if (showSeconds) ...[
                        const SizedBox(height: 18),
                        Row(
                          key: const ValueKey('binary-seconds'),
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            digitColumn(4),
                            SizedBox(width: gap),
                            digitColumn(5),
                          ],
                        ),
                      ],
                    ],
                  ),
                  footer(),
                ],
              ),
            ),
          );
        }

        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showLabels) ...[title(), const SizedBox(height: 18)],
                Row(
                  key: const ValueKey('binary-matrix'),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showLabels) ...[legend(), SizedBox(width: gap * 1.6)],
                    digitColumn(0),
                    SizedBox(width: gap),
                    digitColumn(1),
                    separator(),
                    digitColumn(2),
                    SizedBox(width: gap),
                    digitColumn(3),
                    if (showSeconds)
                      Row(
                        key: const ValueKey('binary-seconds'),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          separator(),
                          digitColumn(4),
                          SizedBox(width: gap),
                          digitColumn(5),
                        ],
                      ),
                  ],
                ),
                footer(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BinaryDot extends StatelessWidget {
  const _BinaryDot({
    required this.on,
    required this.size,
    required this.activeColor,
    required this.inactiveColor,
    required this.borderColor,
  });

  final bool on;
  final double size;
  final Color activeColor;
  final Color inactiveColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: on ? activeColor : inactiveColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: on ? activeColor : borderColor.withValues(alpha: 0.5),
        ),
        boxShadow: on
            ? [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.45),
                  blurRadius: size * 0.6,
                  spreadRadius: size * 0.05,
                ),
              ]
            : null,
      ),
    );
  }
}

class _BigDigitsClockPage extends StatelessWidget {
  const _BigDigitsClockPage({
    required this.now,
    required this.use24Hour,
    required this.portrait,
    required this.showDate,
    required this.showSeconds,
  });

  final DateTime now;
  final bool use24Hour;
  final bool portrait;
  final bool showDate;
  final bool showSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final digits = clockDigitsFor(now, use24Hour: use24Hour);
    final date = MaterialLocalizations.of(context).formatMediumDate(now);
    final style = TextStyle(
      fontSize: 400,
      height: 0.9,
      fontWeight: FontWeight.w700,
      letterSpacing: -12,
      color: scheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget dateLine() => Text(
      date,
      key: const ValueKey('big-date'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );

    Widget secondsLine() => Text(
      '${digits.second} s'
      '${digits.period.isNotEmpty ? ' · ${digits.period}' : ''}',
      key: const ValueKey('big-seconds'),
      style: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    if (portrait) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          children: [
            if (showDate) dateLine(),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Text(digits.hour, style: style),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 32,
                    child: Center(
                      child: Opacity(
                        opacity: now.second.isEven ? 1 : 0.2,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Text(digits.minute, style: style),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showSeconds) secondsLine(),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        children: [
          if (showDate) dateLine(),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(digits.hour, style: style),
                    Opacity(
                      opacity: now.second.isEven ? 1 : 0.2,
                      child: Text(
                        ':',
                        style: style.copyWith(
                          color: scheme.primary,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    Text(digits.minute, style: style),
                  ],
                ),
              ),
            ),
          ),
          if (showSeconds) secondsLine(),
        ],
      ),
    );
  }
}

const List<int> segmentDigitMasks = [63, 6, 91, 79, 102, 109, 125, 7, 127, 111];

const Color _segmentPanelColor = Color(0xff06100e);
const Color _segmentTextColor = Color(0xff9dc4bc);

const List<Color> segmentColorOptions = [
  Color(0xff74f0df),
  Color(0xff86efac),
  Color(0xffffd166),
  Color(0xffff8a80),
  Color(0xff8ab4ff),
  Color(0xffc4a7ff),
  Color(0xffff9ad5),
  Color(0xfff1f5f4),
];

class _SegmentClockPage extends StatelessWidget {
  const _SegmentClockPage({
    required this.now,
    required this.use24Hour,
    required this.portrait,
    required this.scale,
    required this.showSeconds,
    required this.showDate,
    required this.color,
    required this.showBorder,
    required this.borderWidth,
    required this.padding,
    required this.margin,
  });

  final DateTime now;
  final bool use24Hour;
  final bool portrait;
  final double scale;
  final bool showSeconds;
  final bool showDate;
  final Color color;
  final bool showBorder;
  final double borderWidth;
  final double padding;
  final double margin;

  @override
  Widget build(BuildContext context) {
    final digits = clockDigitsFor(now, use24Hour: use24Hour);
    final date = MaterialLocalizations.of(context).formatMediumDate(now);
    final period = digits.period;
    final onColor = color;
    final offColor = Color.lerp(_segmentPanelColor, onColor, 0.18)!;
    final textColor = Color.lerp(_segmentTextColor, onColor, 0.3)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double digitHeight;
        if (portrait) {
          final rows = showSeconds ? 3 : 2;
          final colonRows = rows - 1;
          final horizontalReserve = padding * 2 + margin * 2 + 24;
          final verticalReserve =
              padding * 2 +
              margin * 2 +
              (period.isNotEmpty ? 28.0 : 0.0) +
              (showDate ? 40.0 : 0.0) +
              16;
          final widthRoom = max(
            24.0,
            (constraints.maxWidth - horizontalReserve) / 1.42,
          );
          final heightRoom = max(
            24.0,
            (constraints.maxHeight - verticalReserve) /
                (rows + colonRows * 0.26),
          );
          final fit = min(widthRoom, heightRoom);
          digitHeight = (fit * 0.85 * scale).clamp(24.0, fit);
        } else {
          final digitCount = showSeconds ? 6 : 4;
          final colonCount = showSeconds ? 2 : 1;
          final factor =
              digitCount * 0.68 +
              (colonCount * 2 + 2) * 0.08 +
              colonCount * 0.26;
          final widthRoom = max(
            40.0,
            (constraints.maxWidth - padding * 2 - margin * 2 - 24) / factor,
          );
          final heightRoom = max(
            40.0,
            constraints.maxHeight -
                padding * 2 -
                margin * 2 -
                24 -
                (period.isNotEmpty ? 24.0 : 0.0) -
                (showDate ? 24.0 : 0.0),
          );
          final fit = min(widthRoom, heightRoom);
          digitHeight = (fit * 0.85 * scale).clamp(24.0, fit);
        }
        final digitWidth = digitHeight * 0.68;
        final colonWidth = digitHeight * 0.26;
        final gap = digitHeight * 0.06;

        Widget digit(String value, {bool dotOn = false}) => _SegmentDigit(
          digit: value,
          width: digitWidth,
          height: digitHeight,
          onColor: onColor,
          offColor: offColor,
          dotOn: dotOn,
        );

        Widget colon({required bool compact}) => _SegmentColon(
          width: colonWidth,
          height: compact ? digitHeight * 0.26 : digitHeight,
          dotRadius: compact ? digitHeight * 0.03 : null,
          on: now.second.isEven,
          onColor: onColor,
          offColor: offColor,
        );

        Widget digitsRow(List<String> values, {bool lastDot = false}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            digit(values[0]),
            SizedBox(width: gap),
            digit(values[1], dotOn: lastDot && now.second.isEven),
          ],
        );

        final display = portrait
            ? Column(
                key: const ValueKey('segment-digits'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  digitsRow([digits.hour[0], digits.hour[1]]),
                  colon(compact: true),
                  digitsRow([
                    digits.minute[0],
                    digits.minute[1],
                  ], lastDot: !showSeconds),
                  if (showSeconds) ...[
                    colon(compact: true),
                    Row(
                      key: const ValueKey('segment-seconds'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        digit(digits.second[0]),
                        SizedBox(width: gap),
                        digit(digits.second[1], dotOn: now.second.isEven),
                      ],
                    ),
                  ],
                ],
              )
            : Row(
                key: const ValueKey('segment-digits'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  digit(digits.hour[0]),
                  SizedBox(width: gap),
                  digit(digits.hour[1]),
                  SizedBox(width: gap * 1.5),
                  colon(compact: false),
                  SizedBox(width: gap * 1.5),
                  digit(digits.minute[0]),
                  SizedBox(width: gap),
                  digit(
                    digits.minute[1],
                    dotOn: !showSeconds && now.second.isEven,
                  ),
                  if (showSeconds)
                    Row(
                      key: const ValueKey('segment-seconds'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: gap * 1.5),
                        colon(compact: false),
                        SizedBox(width: gap * 1.5),
                        digit(digits.second[0]),
                        SizedBox(width: gap),
                        digit(digits.second[1], dotOn: now.second.isEven),
                      ],
                    ),
                ],
              );

        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              key: const ValueKey('segment-panel'),
              margin: EdgeInsets.all(margin),
              padding: EdgeInsets.all(padding),
              decoration: BoxDecoration(
                color: _segmentPanelColor,
                borderRadius: BorderRadius.circular(20),
                border: showBorder
                    ? Border.all(
                        color: onColor.withValues(alpha: 0.28),
                        width: borderWidth,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (period.isNotEmpty) ...[
                    Text(
                      period,
                      style: TextStyle(
                        color: onColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  display,
                  if (showDate) ...[
                    const SizedBox(height: 16),
                    Text(
                      date,
                      key: const ValueKey('segment-date'),
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SegmentColorSwatch extends StatelessWidget {
  const _SegmentColorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final checkColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 8),
            ],
          ),
          child: selected
              ? Icon(Icons.check, size: 18, color: checkColor)
              : null,
        ),
      ),
    );
  }
}

class _SegmentDigit extends StatelessWidget {
  const _SegmentDigit({
    required this.digit,
    required this.width,
    required this.height,
    required this.onColor,
    required this.offColor,
    required this.dotOn,
  });

  final String digit;
  final double width;
  final double height;
  final Color onColor;
  final Color offColor;
  final bool dotOn;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(
      painter: _SegmentDigitPainter(
        digit: digit,
        onColor: onColor,
        offColor: offColor,
        dotOn: dotOn,
      ),
    ),
  );
}

class _SegmentDigitPainter extends CustomPainter {
  _SegmentDigitPainter({
    required this.digit,
    required this.onColor,
    required this.offColor,
    required this.dotOn,
  });

  final String digit;
  final Color onColor;
  final Color offColor;
  final bool dotOn;

  @override
  void paint(Canvas canvas, Size size) {
    final value = int.tryParse(digit) ?? 8;
    final mask = value >= 0 && value < segmentDigitMasks.length
        ? segmentDigitMasks[value]
        : 0;
    final t = size.height * 0.11;
    final left = t * 0.55;
    final right = size.width - t * 1.45;
    final top = t * 0.6;
    final bottom = size.height - t * 0.6;
    final middle = size.height / 2;
    final inset = t * 0.75;

    final segments = <(int, Offset, Offset)>[
      (1, Offset(left + inset, top), Offset(right - inset, top)),
      (2, Offset(right, top + inset), Offset(right, middle - inset)),
      (4, Offset(right, middle + inset), Offset(right, bottom - inset)),
      (8, Offset(left + inset, bottom), Offset(right - inset, bottom)),
      (16, Offset(left, middle + inset), Offset(left, bottom - inset)),
      (32, Offset(left, top + inset), Offset(left, middle - inset)),
      (64, Offset(left + inset, middle), Offset(right - inset, middle)),
    ];

    final offPaint = Paint()
      ..color = offColor
      ..strokeWidth = t
      ..strokeCap = StrokeCap.round;
    for (final segment in segments) {
      canvas.drawLine(segment.$2, segment.$3, offPaint);
    }

    final glowPaint = Paint()
      ..color = onColor.withValues(alpha: 0.35)
      ..strokeWidth = t * 1.65
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, t * 0.9);
    final onPaint = Paint()
      ..color = onColor
      ..strokeWidth = t
      ..strokeCap = StrokeCap.round;
    for (final segment in segments) {
      if ((mask & segment.$1) == 0) continue;
      canvas.drawLine(segment.$2, segment.$3, glowPaint);
      canvas.drawLine(segment.$2, segment.$3, onPaint);
    }

    final dotCenter = Offset(size.width - t * 0.55, bottom);
    final dotRadius = t * 0.5;
    if (dotOn) {
      canvas.drawCircle(
        dotCenter,
        dotRadius * 1.8,
        Paint()
          ..color = onColor.withValues(alpha: 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, t * 0.8),
      );
    }
    canvas.drawCircle(
      dotCenter,
      dotRadius,
      Paint()..color = dotOn ? onColor : offColor,
    );
  }

  @override
  bool shouldRepaint(_SegmentDigitPainter oldDelegate) =>
      oldDelegate.digit != digit ||
      oldDelegate.onColor != onColor ||
      oldDelegate.offColor != offColor ||
      oldDelegate.dotOn != dotOn;
}

class _SegmentColon extends StatelessWidget {
  const _SegmentColon({
    required this.width,
    required this.height,
    required this.on,
    required this.onColor,
    required this.offColor,
    this.dotRadius,
  });

  final double width;
  final double height;
  final bool on;
  final Color onColor;
  final Color offColor;
  final double? dotRadius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: CustomPaint(
      painter: _SegmentColonPainter(
        on: on,
        onColor: onColor,
        offColor: offColor,
        dotRadius: dotRadius,
      ),
    ),
  );
}

class _SegmentColonPainter extends CustomPainter {
  _SegmentColonPainter({
    required this.on,
    required this.onColor,
    required this.offColor,
    this.dotRadius,
  });

  final bool on;
  final Color onColor;
  final Color offColor;
  final double? dotRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = dotRadius ?? size.height * 0.055;
    final x = size.width / 2;
    for (final y in [size.height * 0.36, size.height * 0.64]) {
      final center = Offset(x, y);
      if (on) {
        canvas.drawCircle(
          center,
          radius * 1.8,
          Paint()
            ..color = onColor.withValues(alpha: 0.3)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius),
        );
      }
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = on ? onColor : offColor,
      );
    }
  }

  @override
  bool shouldRepaint(_SegmentColonPainter oldDelegate) =>
      oldDelegate.on != on ||
      oldDelegate.onColor != onColor ||
      oldDelegate.offColor != offColor ||
      oldDelegate.dotRadius != dotRadius;
}

// World clock

const List<String> defaultWorldCityIds = [
  'local',
  'london',
  'new-york',
  'tokyo',
];

class WorldCity {
  const WorldCity({
    required this.id,
    required this.englishName,
    required this.chineseName,
    required this.code,
    required this.englishRegion,
    required this.chineseRegion,
    required this.timeZone,
  });

  final String id;
  final String englishName;
  final String chineseName;
  final String code;
  final String englishRegion;
  final String chineseRegion;
  final String? timeZone;

  bool get isLocal => timeZone == null;
}

const localWorldCity = WorldCity(
  id: 'local',
  englishName: 'Local',
  chineseName: '本地',
  code: 'LOC',
  englishRegion: 'This device',
  chineseRegion: '当前设备',
  timeZone: null,
);

const worldCities = <WorldCity>[
  localWorldCity,
  WorldCity(
    id: 'shanghai',
    englishName: 'Shanghai',
    chineseName: '上海',
    code: 'PVG',
    englishRegion: 'China',
    chineseRegion: '中国',
    timeZone: 'Asia/Shanghai',
  ),
  WorldCity(
    id: 'hong-kong',
    englishName: 'Hong Kong',
    chineseName: '香港',
    code: 'HKG',
    englishRegion: 'Hong Kong',
    chineseRegion: '中国香港',
    timeZone: 'Asia/Hong_Kong',
  ),
  WorldCity(
    id: 'taipei',
    englishName: 'Taipei',
    chineseName: '台北',
    code: 'TPE',
    englishRegion: 'Taiwan',
    chineseRegion: '中国台湾',
    timeZone: 'Asia/Taipei',
  ),
  WorldCity(
    id: 'tokyo',
    englishName: 'Tokyo',
    chineseName: '东京',
    code: 'HND',
    englishRegion: 'Japan',
    chineseRegion: '日本',
    timeZone: 'Asia/Tokyo',
  ),
  WorldCity(
    id: 'seoul',
    englishName: 'Seoul',
    chineseName: '首尔',
    code: 'ICN',
    englishRegion: 'South Korea',
    chineseRegion: '韩国',
    timeZone: 'Asia/Seoul',
  ),
  WorldCity(
    id: 'singapore',
    englishName: 'Singapore',
    chineseName: '新加坡',
    code: 'SIN',
    englishRegion: 'Singapore',
    chineseRegion: '新加坡',
    timeZone: 'Asia/Singapore',
  ),
  WorldCity(
    id: 'bangkok',
    englishName: 'Bangkok',
    chineseName: '曼谷',
    code: 'BKK',
    englishRegion: 'Thailand',
    chineseRegion: '泰国',
    timeZone: 'Asia/Bangkok',
  ),
  WorldCity(
    id: 'dubai',
    englishName: 'Dubai',
    chineseName: '迪拜',
    code: 'DXB',
    englishRegion: 'United Arab Emirates',
    chineseRegion: '阿联酋',
    timeZone: 'Asia/Dubai',
  ),
  WorldCity(
    id: 'mumbai',
    englishName: 'Mumbai',
    chineseName: '孟买',
    code: 'BOM',
    englishRegion: 'India',
    chineseRegion: '印度',
    timeZone: 'Asia/Kolkata',
  ),
  WorldCity(
    id: 'delhi',
    englishName: 'Delhi',
    chineseName: '德里',
    code: 'DEL',
    englishRegion: 'India',
    chineseRegion: '印度',
    timeZone: 'Asia/Kolkata',
  ),
  WorldCity(
    id: 'jakarta',
    englishName: 'Jakarta',
    chineseName: '雅加达',
    code: 'CGK',
    englishRegion: 'Indonesia',
    chineseRegion: '印度尼西亚',
    timeZone: 'Asia/Jakarta',
  ),
  WorldCity(
    id: 'manila',
    englishName: 'Manila',
    chineseName: '马尼拉',
    code: 'MNL',
    englishRegion: 'Philippines',
    chineseRegion: '菲律宾',
    timeZone: 'Asia/Manila',
  ),
  WorldCity(
    id: 'kuala-lumpur',
    englishName: 'Kuala Lumpur',
    chineseName: '吉隆坡',
    code: 'KUL',
    englishRegion: 'Malaysia',
    chineseRegion: '马来西亚',
    timeZone: 'Asia/Kuala_Lumpur',
  ),
  WorldCity(
    id: 'doha',
    englishName: 'Doha',
    chineseName: '多哈',
    code: 'DOH',
    englishRegion: 'Qatar',
    chineseRegion: '卡塔尔',
    timeZone: 'Asia/Qatar',
  ),
  WorldCity(
    id: 'riyadh',
    englishName: 'Riyadh',
    chineseName: '利雅得',
    code: 'RUH',
    englishRegion: 'Saudi Arabia',
    chineseRegion: '沙特阿拉伯',
    timeZone: 'Asia/Riyadh',
  ),
  WorldCity(
    id: 'tel-aviv',
    englishName: 'Tel Aviv',
    chineseName: '特拉维夫',
    code: 'TLV',
    englishRegion: 'Israel',
    chineseRegion: '以色列',
    timeZone: 'Asia/Jerusalem',
  ),
  WorldCity(
    id: 'london',
    englishName: 'London',
    chineseName: '伦敦',
    code: 'LHR',
    englishRegion: 'United Kingdom',
    chineseRegion: '英国',
    timeZone: 'Europe/London',
  ),
  WorldCity(
    id: 'paris',
    englishName: 'Paris',
    chineseName: '巴黎',
    code: 'CDG',
    englishRegion: 'France',
    chineseRegion: '法国',
    timeZone: 'Europe/Paris',
  ),
  WorldCity(
    id: 'berlin',
    englishName: 'Berlin',
    chineseName: '柏林',
    code: 'BER',
    englishRegion: 'Germany',
    chineseRegion: '德国',
    timeZone: 'Europe/Berlin',
  ),
  WorldCity(
    id: 'madrid',
    englishName: 'Madrid',
    chineseName: '马德里',
    code: 'MAD',
    englishRegion: 'Spain',
    chineseRegion: '西班牙',
    timeZone: 'Europe/Madrid',
  ),
  WorldCity(
    id: 'rome',
    englishName: 'Rome',
    chineseName: '罗马',
    code: 'FCO',
    englishRegion: 'Italy',
    chineseRegion: '意大利',
    timeZone: 'Europe/Rome',
  ),
  WorldCity(
    id: 'amsterdam',
    englishName: 'Amsterdam',
    chineseName: '阿姆斯特丹',
    code: 'AMS',
    englishRegion: 'Netherlands',
    chineseRegion: '荷兰',
    timeZone: 'Europe/Amsterdam',
  ),
  WorldCity(
    id: 'moscow',
    englishName: 'Moscow',
    chineseName: '莫斯科',
    code: 'SVO',
    englishRegion: 'Russia',
    chineseRegion: '俄罗斯',
    timeZone: 'Europe/Moscow',
  ),
  WorldCity(
    id: 'istanbul',
    englishName: 'Istanbul',
    chineseName: '伊斯坦布尔',
    code: 'IST',
    englishRegion: 'Turkey',
    chineseRegion: '土耳其',
    timeZone: 'Europe/Istanbul',
  ),
  WorldCity(
    id: 'zurich',
    englishName: 'Zurich',
    chineseName: '苏黎世',
    code: 'ZRH',
    englishRegion: 'Switzerland',
    chineseRegion: '瑞士',
    timeZone: 'Europe/Zurich',
  ),
  WorldCity(
    id: 'stockholm',
    englishName: 'Stockholm',
    chineseName: '斯德哥尔摩',
    code: 'ARN',
    englishRegion: 'Sweden',
    chineseRegion: '瑞典',
    timeZone: 'Europe/Stockholm',
  ),
  WorldCity(
    id: 'lisbon',
    englishName: 'Lisbon',
    chineseName: '里斯本',
    code: 'LIS',
    englishRegion: 'Portugal',
    chineseRegion: '葡萄牙',
    timeZone: 'Europe/Lisbon',
  ),
  WorldCity(
    id: 'athens',
    englishName: 'Athens',
    chineseName: '雅典',
    code: 'ATH',
    englishRegion: 'Greece',
    chineseRegion: '希腊',
    timeZone: 'Europe/Athens',
  ),
  WorldCity(
    id: 'reykjavik',
    englishName: 'Reykjavik',
    chineseName: '雷克雅未克',
    code: 'KEF',
    englishRegion: 'Iceland',
    chineseRegion: '冰岛',
    timeZone: 'Atlantic/Reykjavik',
  ),
  WorldCity(
    id: 'new-york',
    englishName: 'New York',
    chineseName: '纽约',
    code: 'JFK',
    englishRegion: 'United States',
    chineseRegion: '美国',
    timeZone: 'America/New_York',
  ),
  WorldCity(
    id: 'los-angeles',
    englishName: 'Los Angeles',
    chineseName: '洛杉矶',
    code: 'LAX',
    englishRegion: 'United States',
    chineseRegion: '美国',
    timeZone: 'America/Los_Angeles',
  ),
  WorldCity(
    id: 'chicago',
    englishName: 'Chicago',
    chineseName: '芝加哥',
    code: 'ORD',
    englishRegion: 'United States',
    chineseRegion: '美国',
    timeZone: 'America/Chicago',
  ),
  WorldCity(
    id: 'denver',
    englishName: 'Denver',
    chineseName: '丹佛',
    code: 'DEN',
    englishRegion: 'United States',
    chineseRegion: '美国',
    timeZone: 'America/Denver',
  ),
  WorldCity(
    id: 'toronto',
    englishName: 'Toronto',
    chineseName: '多伦多',
    code: 'YYZ',
    englishRegion: 'Canada',
    chineseRegion: '加拿大',
    timeZone: 'America/Toronto',
  ),
  WorldCity(
    id: 'vancouver',
    englishName: 'Vancouver',
    chineseName: '温哥华',
    code: 'YVR',
    englishRegion: 'Canada',
    chineseRegion: '加拿大',
    timeZone: 'America/Vancouver',
  ),
  WorldCity(
    id: 'mexico-city',
    englishName: 'Mexico City',
    chineseName: '墨西哥城',
    code: 'MEX',
    englishRegion: 'Mexico',
    chineseRegion: '墨西哥',
    timeZone: 'America/Mexico_City',
  ),
  WorldCity(
    id: 'sao-paulo',
    englishName: 'Sao Paulo',
    chineseName: '圣保罗',
    code: 'GRU',
    englishRegion: 'Brazil',
    chineseRegion: '巴西',
    timeZone: 'America/Sao_Paulo',
  ),
  WorldCity(
    id: 'buenos-aires',
    englishName: 'Buenos Aires',
    chineseName: '布宜诺斯艾利斯',
    code: 'EZE',
    englishRegion: 'Argentina',
    chineseRegion: '阿根廷',
    timeZone: 'America/Argentina/Buenos_Aires',
  ),
  WorldCity(
    id: 'honolulu',
    englishName: 'Honolulu',
    chineseName: '檀香山',
    code: 'HNL',
    englishRegion: 'United States',
    chineseRegion: '美国',
    timeZone: 'Pacific/Honolulu',
  ),
  WorldCity(
    id: 'anchorage',
    englishName: 'Anchorage',
    chineseName: '安克雷奇',
    code: 'ANC',
    englishRegion: 'United States',
    chineseRegion: '美国',
    timeZone: 'America/Anchorage',
  ),
  WorldCity(
    id: 'lima',
    englishName: 'Lima',
    chineseName: '利马',
    code: 'LIM',
    englishRegion: 'Peru',
    chineseRegion: '秘鲁',
    timeZone: 'America/Lima',
  ),
  WorldCity(
    id: 'bogota',
    englishName: 'Bogota',
    chineseName: '波哥大',
    code: 'BOG',
    englishRegion: 'Colombia',
    chineseRegion: '哥伦比亚',
    timeZone: 'America/Bogota',
  ),
  WorldCity(
    id: 'sydney',
    englishName: 'Sydney',
    chineseName: '悉尼',
    code: 'SYD',
    englishRegion: 'Australia',
    chineseRegion: '澳大利亚',
    timeZone: 'Australia/Sydney',
  ),
  WorldCity(
    id: 'melbourne',
    englishName: 'Melbourne',
    chineseName: '墨尔本',
    code: 'MEL',
    englishRegion: 'Australia',
    chineseRegion: '澳大利亚',
    timeZone: 'Australia/Melbourne',
  ),
  WorldCity(
    id: 'perth',
    englishName: 'Perth',
    chineseName: '珀斯',
    code: 'PER',
    englishRegion: 'Australia',
    chineseRegion: '澳大利亚',
    timeZone: 'Australia/Perth',
  ),
  WorldCity(
    id: 'auckland',
    englishName: 'Auckland',
    chineseName: '奥克兰',
    code: 'AKL',
    englishRegion: 'New Zealand',
    chineseRegion: '新西兰',
    timeZone: 'Pacific/Auckland',
  ),
  WorldCity(
    id: 'cairo',
    englishName: 'Cairo',
    chineseName: '开罗',
    code: 'CAI',
    englishRegion: 'Egypt',
    chineseRegion: '埃及',
    timeZone: 'Africa/Cairo',
  ),
  WorldCity(
    id: 'johannesburg',
    englishName: 'Johannesburg',
    chineseName: '约翰内斯堡',
    code: 'JNB',
    englishRegion: 'South Africa',
    chineseRegion: '南非',
    timeZone: 'Africa/Johannesburg',
  ),
  WorldCity(
    id: 'lagos',
    englishName: 'Lagos',
    chineseName: '拉各斯',
    code: 'LOS',
    englishRegion: 'Nigeria',
    chineseRegion: '尼日利亚',
    timeZone: 'Africa/Lagos',
  ),
  WorldCity(
    id: 'nairobi',
    englishName: 'Nairobi',
    chineseName: '内罗毕',
    code: 'NBO',
    englishRegion: 'Kenya',
    chineseRegion: '肯尼亚',
    timeZone: 'Africa/Nairobi',
  ),
  WorldCity(
    id: 'casablanca',
    englishName: 'Casablanca',
    chineseName: '卡萨布兰卡',
    code: 'CAS',
    englishRegion: 'Morocco',
    chineseRegion: '摩洛哥',
    timeZone: 'Africa/Casablanca',
  ),
];

final Map<String, WorldCity> _worldCityIndex = {
  for (final city in worldCities) city.id: city,
};

WorldCity? worldCityById(String id) => _worldCityIndex[id];

bool _worldTimeZonesReady = false;
final Map<String, tz.Location> _worldLocationCache = {};

void ensureWorldTimeZones() {
  if (_worldTimeZonesReady) return;
  tzdata.initializeTimeZones();
  _worldTimeZonesReady = true;
}

tz.Location _worldLocation(String timeZone) =>
    _worldLocationCache.putIfAbsent(timeZone, () => tz.getLocation(timeZone));

DateTime worldCityTime(WorldCity city, DateTime instant) {
  final timeZone = city.timeZone;
  if (timeZone == null) return instant;
  ensureWorldTimeZones();
  try {
    return tz.TZDateTime.from(instant, _worldLocation(timeZone));
  } catch (_) {
    return instant.toUtc();
  }
}

String worldClockOffsetLabel(Duration offset) {
  final minutes = offset.inMinutes;
  final sign = minutes < 0 ? '-' : '+';
  final absolute = minutes.abs();
  final hours = (absolute ~/ 60).toString().padLeft(2, '0');
  final rest = (absolute % 60).toString().padLeft(2, '0');
  return 'UTC$sign$hours:$rest';
}

bool worldClockIsDay(DateTime now) => now.hour >= 6 && now.hour < 18;

enum WorldSignMode { text, flip, cards }

extension WorldSignModeDetails on WorldSignMode {
  String get englishName => switch (this) {
    WorldSignMode.text => 'Text',
    WorldSignMode.flip => 'Flip',
    WorldSignMode.cards => 'Cards',
  };

  String get chineseName => switch (this) {
    WorldSignMode.text => '文字',
    WorldSignMode.flip => '翻页',
    WorldSignMode.cards => '纯卡片',
  };
}

class WorldClockSettings {
  WorldClockSettings() : cityIds = [...defaultWorldCityIds];

  List<String> cityIds;
  bool use24Hour = true;
  bool showSeconds = false;
  bool showDate = true;
  WorldSignMode signMode = WorldSignMode.text;

  void resetCities() {
    cityIds = [...defaultWorldCityIds];
  }

  void reset() {
    resetCities();
    use24Hour = true;
    showSeconds = false;
    showDate = true;
    signMode = WorldSignMode.text;
  }

  Map<String, dynamic> toJson() => {
    'cities': cityIds,
    'use24': use24Hour,
    'seconds': showSeconds,
    'date': showDate,
    'signMode': signMode.name,
  };

  factory WorldClockSettings.fromJson(Map<String, dynamic> json) {
    final settings = WorldClockSettings();
    final cities = json['cities'];
    if (cities is List) {
      settings.cityIds.clear();
      final seen = <String>{};
      for (final value in cities) {
        if (value is String &&
            worldCityById(value) != null &&
            seen.add(value)) {
          settings.cityIds.add(value);
        }
      }
    }
    if (json['use24'] case final bool value) settings.use24Hour = value;
    if (json['seconds'] case final bool value) settings.showSeconds = value;
    if (json['date'] case final bool value) settings.showDate = value;
    settings.signMode = switch (json['signMode']) {
      'flip' => WorldSignMode.flip,
      'cards' => WorldSignMode.cards,
      _ => WorldSignMode.text,
    };
    return settings;
  }
}

const Color _worldBoardBackground = Color(0xff0b0f11);
const Color _worldBoardSurface = Color(0xff141a1d);
const Color _worldBoardCard = Color(0xff090c0e);
const Color _worldBoardBorder = Color(0xff273136);
const Color _worldBoardText = Color(0xfff2ece2);
const Color _worldBoardMuted = Color(0xff8c989d);
const Color _worldBoardAccent = Color(0xffe8b45a);
const Color _worldBoardNight = Color(0xff82a9c9);

class WorldClockScreen extends StatefulWidget {
  const WorldClockScreen({super.key, this.preferences});

  final LocalPreferences? preferences;

  @override
  State<WorldClockScreen> createState() => _WorldClockScreenState();
}

class _WorldClockScreenState extends State<WorldClockScreen>
    with WidgetsBindingObserver {
  late final LocalPreferences _preferences;
  WorldClockSettings _settings = WorldClockSettings();
  DateTime _now = DateTime.now();
  Timer? _ticker;
  Timer? _saveTimer;
  bool _settingsTouched = false;
  bool _backgrounded = false;

  @override
  void initState() {
    super.initState();
    ensureWorldTimeZones();
    _preferences =
        widget.preferences ?? LocalPreferences.forFile('tool_world_clock.json');
    WidgetsBinding.instance.addObserver(this);
    _scheduleTick();
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _saveTimer?.cancel();
    if (_settingsTouched) unawaited(_saveSettings());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
      _ticker?.cancel();
      _saveTimer?.cancel();
      if (_settingsTouched) unawaited(_saveSettings());
    }
  }

  void _scheduleTick() {
    _ticker?.cancel();
    if (_backgrounded) return;
    final now = DateTime.now();
    _ticker = Timer(Duration(milliseconds: 1000 - now.millisecond), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleTick();
    });
  }

  Future<void> _loadSettings() async {
    final raw = await _preferences.getString('settings');
    if (!mounted || raw == null || _settingsTouched) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final loaded = WorldClockSettings.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      setState(() => _settings = loaded);
    } catch (_) {
      // Keep the defaults when the stored data cannot be read.
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _preferences.setString('settings', jsonEncode(_settings.toJson()));
    } catch (_) {}
  }

  void _scheduleSave() {
    _settingsTouched = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 150), () {
      unawaited(_saveSettings());
    });
  }

  void _mutateSettings(VoidCallback update) {
    setState(update);
    _scheduleSave();
  }

  void _toggleCity(WorldCity city) {
    _mutateSettings(() {
      if (!_settings.cityIds.remove(city.id)) {
        _settings.cityIds.add(city.id);
      }
    });
  }

  void _removeCity(String id) {
    _mutateSettings(() => _settings.cityIds.remove(id));
  }

  Future<void> _openCityPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final inset = media.viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: SizedBox(
            height: (media.size.height - inset) * 0.86,
            child: _WorldCityPicker(
              selectedIds: _settings.cityIds,
              use24Hour: _settings.use24Hour,
              onToggle: _toggleCity,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openBoardSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          void refresh() => setSheetState(() {});
          return _boardSettingsSheet(context, refresh);
        },
      ),
    );
  }

  Widget _boardSettingsSheet(BuildContext context, VoidCallback refresh) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(context, 'Board settings', '翻页牌设置'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('world-clock-use24'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, '24-hour time', '24 小时制')),
              subtitle: Text(
                tr(
                  context,
                  'Airport boards normally use 24-hour time.',
                  '机场翻页牌通常使用 24 小时制。',
                ),
              ),
              value: _settings.use24Hour,
              onChanged: (value) {
                _mutateSettings(() => _settings.use24Hour = value);
                refresh();
              },
            ),
            SwitchListTile(
              key: const ValueKey('world-clock-seconds'),
              contentPadding: EdgeInsets.zero,
              title: Text(tr(context, 'Show seconds', '显示秒数')),
              subtitle: Text(
                tr(
                  context,
                  'Add a small seconds pair beside the minutes.',
                  '在分钟右侧增加一组小秒数翻页。',
                ),
              ),
              value: _settings.showSeconds,
              onChanged: (value) {
                _mutateSettings(() => _settings.showSeconds = value);
                refresh();
              },
            ),
            SwitchListTile(
              key: const ValueKey('world-clock-date'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                tr(context, 'Date, offset and day/night', '日期、时差与昼夜'),
              ),
              subtitle: Text(
                tr(
                  context,
                  'Show the local date, UTC offset and a day or night mark.',
                  '显示当地日期、UTC 时差和昼夜标记。',
                ),
              ),
              value: _settings.showDate,
              onChanged: (value) {
                _mutateSettings(() => _settings.showDate = value);
                refresh();
              },
            ),
            const SizedBox(height: 6),
            Text(
              tr(context, 'Display', '显示样式'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<WorldSignMode>(
              key: const ValueKey('world-clock-sign-mode'),
              showSelectedIcon: false,
              style: const ButtonStyle(
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              segments: [
                for (final mode in WorldSignMode.values)
                  ButtonSegment(
                    value: mode,
                    icon: Icon(switch (mode) {
                      WorldSignMode.text => Icons.title,
                      WorldSignMode.flip => Icons.flip_to_front_outlined,
                      WorldSignMode.cards => Icons.style_outlined,
                    }),
                    label: Text(
                      tr(context, mode.englishName, mode.chineseName),
                    ),
                  ),
              ],
              selected: {_settings.signMode},
              onSelectionChanged: (selection) {
                _mutateSettings(() => _settings.signMode = selection.first);
                refresh();
              },
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                context,
                'Flip turns every letter of the city name into a split-flap card. '
                    'Cards shows only the flip cards and hides the code, subtitle, '
                    'date and small text.',
                '翻页会把城市名的每个字母做成卡片；纯卡片只显示翻页卡片，'
                    '隐藏代码、小字、日期和描述。',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 28),
            ListTile(
              key: const ValueKey('world-clock-reset'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restart_alt),
              title: Text(tr(context, 'Restore default cities', '恢复默认城市')),
              subtitle: Text(
                tr(
                  context,
                  'Local, London, New York and Tokyo.',
                  '本地、伦敦、纽约和东京。',
                ),
              ),
              onTap: () {
                _mutateSettings(_settings.resetCities);
                refresh();
              },
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                context,
                'Times include daylight saving and update every second.',
                '时间包含夏令时，并每秒更新。',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardHeader(BuildContext context, int count) {
    final utc = _now.toUtc();
    final utcTime =
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')}:'
        '${utc.second.toString().padLeft(2, '0')}';
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(_now)
        .toUpperCase();
    return Column(
      key: const ValueKey('world-clock-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: _worldBoardAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(context, 'WORLD TIME', '世界时间'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3.4,
                  color: _worldBoardAccent,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'UTC $utcTime',
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                color: _worldBoardMuted,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: Text(
                '${tr(context, 'LIVE BOARD', '实时看板')} · $count '
                '${tr(context, count == 1 ? 'CITY' : 'CITIES', '个城市')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: _worldBoardMuted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                date,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: _worldBoardMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(height: 1, color: _worldBoardAccent.withValues(alpha: 0.22)),
      ],
    );
  }

  Widget _emptyBoard(BuildContext context) => Container(
    key: const ValueKey('world-clock-empty'),
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 42, 24, 36),
    decoration: BoxDecoration(
      color: _worldBoardSurface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _worldBoardBorder),
    ),
    child: Column(
      children: [
        const Icon(Icons.public, size: 42, color: _worldBoardAccent),
        const SizedBox(height: 14),
        Text(
          tr(context, 'The board is empty', '看板还没有城市'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _worldBoardText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            context,
            'Add a timezone to start the departures board.',
            '添加一个时区，开始显示翻页牌。',
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: _worldBoardMuted),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          key: const ValueKey('world-clock-empty-add'),
          onPressed: _openCityPicker,
          icon: const Icon(Icons.add),
          label: Text(tr(context, 'Add timezone', '添加时区')),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cities = [for (final id in _settings.cityIds) ?worldCityById(id)];
    final cardsOnly = _settings.signMode == WorldSignMode.cards;
    return Scaffold(
      backgroundColor: _worldBoardBackground,
      appBar: AppBar(
        backgroundColor: _worldBoardBackground,
        foregroundColor: _worldBoardText,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Text(tr(context, 'World Clock', '世界时钟')),
        actions: [
          IconButton(
            key: const ValueKey('world-clock-add'),
            tooltip: tr(context, 'Add timezone', '添加时区'),
            onPressed: _openCityPicker,
            icon: const Icon(Icons.add),
          ),
          IconButton(
            key: const ValueKey('world-clock-settings'),
            tooltip: tr(context, 'Board settings', '翻页牌设置'),
            onPressed: _openBoardSettings,
            icon: const Icon(Icons.tune),
          ),
          toolInfoAction(context, 'world-clock'),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _worldBoardBorder),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_worldBoardBackground, Color(0xff070a0b)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  if (!cardsOnly) ...[
                    _boardHeader(context, cities.length),
                    const SizedBox(height: 18),
                  ],
                  if (cities.isEmpty)
                    _emptyBoard(context)
                  else
                    for (var index = 0; index < cities.length; index++) ...[
                      _WorldClockRow(
                        key: ValueKey('world-clock-city-${cities[index].id}'),
                        city: cities[index],
                        now: _now,
                        use24Hour: _settings.use24Hour,
                        showSeconds: _settings.showSeconds,
                        showDate: _settings.showDate,
                        signMode: _settings.signMode,
                        onRemove: () => _removeCity(cities[index].id),
                      ),
                      if (index < cities.length - 1) const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorldClockRow extends StatelessWidget {
  const _WorldClockRow({
    super.key,
    required this.city,
    required this.now,
    required this.use24Hour,
    required this.showSeconds,
    required this.showDate,
    required this.signMode,
    required this.onRemove,
  });

  final WorldCity city;
  final DateTime now;
  final bool use24Hour;
  final bool showSeconds;
  final bool showDate;
  final WorldSignMode signMode;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final time = worldCityTime(city, now);
    final digits = clockDigitsFor(time, use24Hour: use24Hour);
    final offset = worldClockOffsetLabel(time.timeZoneOffset);
    final zone = time.timeZoneName.trim();
    final day = worldClockIsDay(time);
    final date = MaterialLocalizations.of(context)
        .formatMediumDate(time)
        .toUpperCase();
    final chineseLocale = Localizations.localeOf(context).languageCode == 'zh';
    final cardsOnly = signMode == WorldSignMode.cards;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;

        Widget codeBadge() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _worldBoardAccent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            city.code,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Color(0xff1d1305),
            ),
          ),
        );

        Widget cityTitle() => Text(
          city.englishName.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: wide ? 22 : 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.4,
            color: _worldBoardText,
          ),
        );

        Widget flipSign({required bool wide}) {
          final cardWidth = wide ? (cardsOnly ? 24.0 : 20.0) : 16.0;
          final cardHeight = cardWidth * 1.35;
          final gap = wide ? 3.0 : 2.4;
          final space = wide ? 10.0 : 8.0;
          final letters = city.englishName.toUpperCase().split('');
          final children = <Widget>[];
          for (final letter in letters) {
            if (letter == ' ') {
              children.add(SizedBox(width: space));
            } else {
              children.add(
                _FlipCard(
                  digit: letter,
                  width: cardWidth,
                  height: cardHeight,
                  background: _worldBoardCard,
                  foreground: _worldBoardText,
                  divider: _worldBoardBorder,
                ),
              );
              children.add(SizedBox(width: gap));
            }
          }
          if (children.isNotEmpty) children.removeLast();
          return FittedBox(
            key: ValueKey('world-clock-sign-${city.id}'),
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          );
        }

        Widget cityHead({required bool wide}) {
          if (signMode == WorldSignMode.text) {
            return Row(
              children: [
                codeBadge(),
                const SizedBox(width: 10),
                Expanded(child: cityTitle()),
              ],
            );
          }
          if (cardsOnly) return flipSign(wide: wide);
          if (wide) {
            return Row(
              children: [
                codeBadge(),
                const SizedBox(width: 10),
                Expanded(child: flipSign(wide: true)),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              codeBadge(),
              const SizedBox(height: 8),
              flipSign(wide: false),
            ],
          );
        }

        Widget citySubtitle() {
          final region = tr(context, city.englishRegion, city.chineseRegion);
          return Padding(
            key: ValueKey('world-clock-subtitle-${city.id}'),
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              chineseLocale ? '${city.chineseName} · $region' : region,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                letterSpacing: 0.3,
                color: _worldBoardMuted,
              ),
            ),
          );
        }

        Widget removeButton() => IconButton(
          key: ValueKey('world-clock-remove-${city.id}'),
          tooltip: tr(
            context,
            'Remove ${city.englishName}',
            '移除${city.chineseName}',
          ),
          onPressed: onRemove,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          icon: const Icon(Icons.close, size: 18),
          color: _worldBoardMuted,
        );

        Widget meta() => Padding(
          key: ValueKey('world-clock-meta-${city.id}'),
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Icon(
                day ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
                size: 13,
                color: day ? _worldBoardAccent : _worldBoardNight,
              ),
              const SizedBox(width: 5),
              Text(
                day ? tr(context, 'DAY', '白天') : tr(context, 'NIGHT', '夜间'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: day ? _worldBoardAccent : _worldBoardNight,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '·',
                style: TextStyle(fontSize: 10, color: _worldBoardMuted),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$date · $offset${zone.isEmpty ? '' : ' · $zone'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 0.6,
                    color: _worldBoardMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        );

        Widget flipCard(String digit, double width) {
          final height = width * 1.32;
          return _FlipCard(
            digit: digit,
            width: width,
            height: height,
            background: _worldBoardCard,
            foreground: _worldBoardText,
            divider: _worldBoardBorder,
          );
        }

        Widget pair(String value, double width) {
          final gap = width * 0.09;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              flipCard(value[0], width),
              SizedBox(width: gap),
              flipCard(value[1], width),
            ],
          );
        }

        Widget colonDots(double height, double width) {
          Widget dot() => Container(
            width: width * 0.24,
            height: width * 0.24,
            decoration: const BoxDecoration(
              color: _worldBoardAccent,
              shape: BoxShape.circle,
            ),
          );

          return SizedBox(
            width: width,
            height: height,
            child: Center(
              child: Opacity(
                opacity: time.second.isEven ? 1 : 0.55,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot(),
                    SizedBox(height: height * 0.16),
                    dot(),
                  ],
                ),
              ),
            ),
          );
        }

        Widget timeGroup({required bool compact}) {
          final width = compact ? 34.0 : 38.0;
          final height = width * 1.32;
          final colonWidth = compact ? 16.0 : 19.0;
          final secondWidth = width * 0.7;
          return Semantics(
            label:
                '${city.englishName} ${digits.hour}:${digits.minute}'
                '${showSeconds ? ':${digits.second}' : ''} '
                '${digits.period}',
            child: Row(
              key: ValueKey('world-clock-time-${city.id}'),
              mainAxisSize: MainAxisSize.min,
              children: [
                pair(digits.hour, width),
                colonDots(height, colonWidth),
                pair(digits.minute, width),
                if (showSeconds) ...[
                  SizedBox(width: compact ? 6 : 8),
                  Container(
                    width: 1,
                    height: height * 0.8,
                    color: _worldBoardBorder,
                  ),
                  SizedBox(width: compact ? 6 : 8),
                  KeyedSubtree(
                    key: ValueKey('world-clock-seconds-${city.id}'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        flipCard(digits.second[0], secondWidth),
                        SizedBox(width: secondWidth * 0.09),
                        flipCard(digits.second[1], secondWidth),
                      ],
                    ),
                  ),
                ],
                if (digits.period.isNotEmpty) ...[
                  SizedBox(width: compact ? 6 : 8),
                  if (cardsOnly)
                    KeyedSubtree(
                      key: ValueKey('world-clock-period-${city.id}'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          flipCard(digits.period[0], secondWidth),
                          SizedBox(width: secondWidth * 0.09),
                          flipCard(digits.period[1], secondWidth),
                        ],
                      ),
                    )
                  else
                    Text(
                      digits.period,
                      style: TextStyle(
                        fontSize: compact ? 10 : 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: _worldBoardAccent,
                      ),
                    ),
                ],
              ],
            ),
          );
        }

        Widget content;
        if (cardsOnly) {
          content = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: cityHead(wide: true)),
                    const SizedBox(width: 18),
                    timeGroup(compact: false),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cityHead(wide: false),
                    const SizedBox(height: 12),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: timeGroup(compact: true),
                    ),
                  ],
                );
        } else if (wide) {
          content = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cityHead(wide: true),
                    citySubtitle(),
                    if (showDate) meta(),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              timeGroup(compact: false),
            ],
          );
        } else {
          content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              cityHead(wide: false),
              citySubtitle(),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: timeGroup(compact: true),
              ),
              if (showDate) meta(),
            ],
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: _worldBoardSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _worldBoardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  color: _worldBoardAccent.withValues(alpha: 0.6),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 14, cardsOnly ? 16 : 46, 14),
                child: content,
              ),
              if (!cardsOnly)
                Positioned(top: 4, right: 4, child: removeButton()),
            ],
          ),
        );
      },
    );
  }
}

class _WorldCityPicker extends StatefulWidget {
  const _WorldCityPicker({
    required this.selectedIds,
    required this.use24Hour,
    required this.onToggle,
  });

  final List<String> selectedIds;
  final bool use24Hour;
  final ValueChanged<WorldCity> onToggle;

  @override
  State<_WorldCityPicker> createState() => _WorldCityPickerState();
}

class _WorldCityPickerState extends State<_WorldCityPicker> {
  late final Set<String> _selected = widget.selectedIds.toSet();
  late final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<WorldCity> get _filtered {
    final query = _query.trim().toLowerCase();
    final cities = worldCities.where((city) {
      if (query.isEmpty) return true;
      return city.englishName.toLowerCase().contains(query) ||
          city.chineseName.contains(query) ||
          city.code.toLowerCase().contains(query) ||
          city.englishRegion.toLowerCase().contains(query) ||
          city.chineseRegion.contains(query) ||
          (city.timeZone?.toLowerCase().contains(query) ?? false) ||
          (city.isLocal && ('local'.contains(query) || '本地'.contains(query)));
    }).toList();
    cities.sort((a, b) {
      if (a.isLocal) return -1;
      if (b.isLocal) return 1;
      return a.englishName.compareTo(b.englishName);
    });
    return cities;
  }

  void _toggle(WorldCity city) {
    setState(() {
      if (!_selected.remove(city.id)) _selected.add(city.id);
    });
    widget.onToggle(city);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chineseLocale = Localizations.localeOf(context).languageCode == 'zh';
    final cities = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(context, 'Add cities', '添加城市'),
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_selected.length} ${tr(context, 'selected', '已选择')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('world-clock-picker-done'),
                onPressed: () => Navigator.pop(context),
                child: Text(tr(context, 'Done', '完成')),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            key: const ValueKey('world-clock-search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr(
                context,
                'Search city, code or timezone',
                '搜索城市、代码或时区',
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: cities.isEmpty
              ? Center(
                  child: Text(
                    tr(context, 'No matching cities', '没有匹配的城市'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  key: const ValueKey('world-clock-picker-list'),
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                  itemCount: cities.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    final city = cities[index];
                    final time = worldCityTime(city, DateTime.now());
                    final digits = clockDigitsFor(
                      time,
                      use24Hour: widget.use24Hour,
                    );
                    final offset = worldClockOffsetLabel(time.timeZoneOffset);
                    final zone = time.timeZoneName.trim();
                    return CheckboxListTile(
                      key: ValueKey('world-clock-picker-${city.id}'),
                      value: _selected.contains(city.id),
                      onChanged: (_) => _toggle(city),
                      controlAffinity: ListTileControlAffinity.trailing,
                      secondary: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          city.code,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                      title: Text(
                        city.englishName.toUpperCase(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chineseLocale
                                ? '${city.chineseName} · '
                                      '${tr(context, city.englishRegion, city.chineseRegion)}'
                                : tr(
                                    context,
                                    city.englishRegion,
                                    city.chineseRegion,
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${digits.hour}:${digits.minute}'
                            '${digits.period.isNotEmpty ? ' ${digits.period}' : ''}'
                            ' · $offset'
                            '${zone.isEmpty ? '' : ' · $zone'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      dense: true,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class VaultNote {
  VaultNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.images = const [],
  });
  final String id;
  String title;
  String body;
  DateTime updatedAt;
  List<String> images;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt.toIso8601String(),
    'images': images,
  };
  factory VaultNote.fromJson(Map<String, dynamic> json) => VaultNote(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    images: List<String>.from(json['images'] as List? ?? const []),
  );
}

enum VaultLockType { pattern, pin }

class VaultStore {
  VaultStore([this._directory]);

  static const _format = 'PVLT2';
  static const _iterations = 210000;
  static const _fileName = 'pockito-cache.pvlt';
  final _cipher = AesGcm.with256bits();
  final _random = Random.secure();
  final Directory? _directory;
  late File _file;
  List<VaultNote> notes = [];
  SecretKey? _dataKey;
  VaultLockType? _lockType;
  bool _exists = false;

  Future<void> initialize() async {
    final directory = _directory ?? await getApplicationSupportDirectory();
    _file = File('${directory.path}${Platform.pathSeparator}$_fileName');
    await _recoverInterruptedWrite();
    final envelope = await _readEnvelope(_file);
    _exists = envelope != null;
    _lockType = _lockTypeOf(envelope);
  }

  VaultLockType? _lockTypeOf(Map<String, dynamic>? envelope) {
    if (envelope == null) return null;
    try {
      return VaultLockType.values.byName(envelope['type'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _readEnvelope(File file) async {
    try {
      if (!await file.exists()) return null;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic> ||
          value['format'] != _format ||
          value['salt'] is! String ||
          value['payload'] is! Map) {
        return null;
      }
      VaultLockType.values.byName(value['type'] as String);
      _decode(value['salt'] as String);
      final payload = Map<String, dynamic>.from(value['payload'] as Map);
      _decode(payload['nonce'] as String);
      _decode(payload['ciphertext'] as String);
      _decode(payload['mac'] as String);
      return value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _recoverInterruptedWrite() async {
    final temporary = File('${_file.path}.writing');
    final backup = File('${_file.path}.backup');
    final mainExists = await _file.exists();
    final mainValid = await _readEnvelope(_file) != null;

    if (!mainValid && await _readEnvelope(temporary) != null) {
      if (mainExists) await _file.delete();
      await temporary.rename(_file.path);
    } else if (!mainValid && await _readEnvelope(backup) != null) {
      if (mainExists) await _file.delete();
      await backup.rename(_file.path);
    }
    if (await temporary.exists()) await temporary.delete();
    if (await backup.exists()) await backup.delete();
  }

  bool get exists => _exists;
  VaultLockType? get lockType => _lockType;

  List<int> _bytes(int count) =>
      List<int>.generate(count, (_) => _random.nextInt(256));
  String _encode(List<int> bytes) => base64UrlEncode(bytes);
  List<int> _decode(String value) =>
      base64Url.decode(base64Url.normalize(value));

  Future<SecretKey> _derive(String secret, List<int> salt) => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  ).deriveKey(secretKey: SecretKey(utf8.encode(secret)), nonce: salt);

  Future<void> create({
    required VaultLockType type,
    required String secret,
  }) async {
    final salt = _bytes(16);
    _dataKey = await _derive(secret, salt);
    _lockType = type;
    notes = [];
    await _write(type: type, salt: salt);
    _exists = true;
  }

  Future<bool> unlock(String secret) async {
    final envelope = await _readEnvelope(_file);
    if (envelope == null) return false;
    final key = await _derive(secret, _decode(envelope['salt'] as String));
    try {
      await _loadPayload(envelope, key);
    } on SecretBoxAuthenticationError {
      return false;
    }
    _dataKey = key;
    _lockType = _lockTypeOf(envelope);
    return true;
  }

  Future<void> _loadPayload(
    Map<String, dynamic> envelope,
    SecretKey key,
  ) async {
    final payload = Map<String, dynamic>.from(envelope['payload'] as Map);
    final plain = await _cipher.decrypt(
      SecretBox(
        _decode(payload['ciphertext'] as String),
        nonce: _decode(payload['nonce'] as String),
        mac: Mac(_decode(payload['mac'] as String)),
      ),
      secretKey: key,
    );
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    notes = (json['notes'] as List? ?? [])
        .map(
          (item) => VaultNote.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> save() async {
    final envelope = await _readEnvelope(_file);
    if (envelope == null) return;
    await _write(
      type: VaultLockType.values.byName(envelope['type'] as String),
      salt: _decode(envelope['salt'] as String),
    );
  }

  Future<void> _write({
    required VaultLockType type,
    required List<int> salt,
  }) async {
    final plain = utf8.encode(
      jsonEncode({'notes': notes.map((note) => note.toJson()).toList()}),
    );
    final box = await _cipher.encrypt(
      plain,
      secretKey: _dataKey!,
      nonce: _bytes(12),
    );
    final document = jsonEncode({
      'format': _format,
      'version': 2,
      'type': type.name,
      'salt': _encode(salt),
      'payload': {
        'nonce': _encode(box.nonce),
        'ciphertext': _encode(box.cipherText),
        'mac': _encode(box.mac.bytes),
      },
    });
    final temporary = File('${_file.path}.writing');
    final handle = await temporary.open(mode: FileMode.write);
    await handle.writeString(document);
    await handle.flush();
    await handle.close();
    final backup = File('${_file.path}.backup');
    if (await backup.exists()) await backup.delete();
    if (await _file.exists()) await _file.rename(backup.path);
    try {
      await temporary.rename(_file.path);
    } catch (_) {
      if (!await _file.exists() && await backup.exists()) {
        await backup.rename(_file.path);
      }
      rethrow;
    }
    if (await backup.exists()) await backup.delete();
  }
}

class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key});
  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  final _random = Random.secure();
  final _seedController = TextEditingController();
  int _length = 20;
  bool _lowercase = true;
  bool _uppercase = true;
  bool _numbers = true;
  bool _special = true;
  bool _unique = false;
  bool _excludeAmbiguous = false;
  bool _highlight = true;
  String _seed = '';
  String _password = '';
  String? _error;
  final _trace = <Offset>[];

  void _addTracePoint(Offset point) {
    const maximumTracePoints = 512;
    if (_trace.length == maximumTracePoints) {
      _trace.removeAt(0);
    }
    _trace.add(point);
  }

  @override
  void initState() {
    super.initState();
    _password = _makePassword();
  }

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  String get _pool {
    final parts = <String>[];
    if (_lowercase) parts.add('abcdefghijklmnopqrstuvwxyz');
    if (_uppercase) parts.add('ABCDEFGHIJKLMNOPQRSTUVWXYZ');
    if (_numbers) parts.add('0123456789');
    if (_special) parts.add('!@#%+=?_-.,:;');
    final pool = parts.join();
    if (!_excludeAmbiguous) return pool;
    return pool
        .split('')
        .where((character) => !'0O1Il'.contains(character))
        .join();
  }

  int _seedValue() {
    var value = 2166136261;
    for (final codeUnit in _seed.codeUnits) {
      value ^= codeUnit;
      value = (value * 16777619) & 0x7fffffff;
    }
    for (var index = 0; index < _trace.length; index++) {
      final point = _trace[index];
      value ^= point.dx.round() + point.dy.round() * 31 + index * 131;
      value = (value * 16777619) & 0x7fffffff;
    }
    return value;
  }

  String _makePassword() {
    final pool = _pool;
    if (pool.isEmpty || (_unique && _length > pool.length)) return '';
    final seedValue = _seedValue();
    final available = pool.split('');
    return List<String>.generate(_length, (index) {
      var position = _random.nextInt(_unique ? available.length : pool.length);
      if (_seed.isNotEmpty || _trace.isNotEmpty) {
        position =
            (position + ((seedValue >> (index % 24)) & 0x7fffffff)) %
            (_unique ? available.length : pool.length);
      }
      if (_unique) return available.removeAt(position);
      return pool[position];
    }).join();
  }

  void _regenerate() {
    if (_pool.isEmpty) {
      setState(() {
        _password = '';
        _error = tr(
          context,
          'Select at least one character type.',
          '请至少选择一种字符类型。',
        );
      });
      return;
    }
    if (_unique && _length > _pool.length) {
      setState(() {
        _password = '';
        _error = tr(
          context,
          'Unique mode supports up to ${_pool.length} characters with the current filters.',
          '当前筛选条件下，唯一字符模式最多支持 ${_pool.length} 位。',
        );
      });
      return;
    }
    setState(() {
      _password = _makePassword();
      _error = null;
    });
  }

  void _resetDefaults() {
    _seedController.clear();
    setState(() {
      _length = 20;
      _lowercase = true;
      _uppercase = true;
      _numbers = true;
      _special = true;
      _unique = false;
      _excludeAmbiguous = false;
      _highlight = true;
      _seed = '';
      _trace.clear();
      _error = null;
      _password = _makePassword();
    });
  }

  Color _characterColor(String character, BuildContext context) {
    if (!_highlight) return Theme.of(context).colorScheme.onSurface;
    if (RegExp(r'[a-z]').hasMatch(character)) return const Color(0xff13795b);
    if (RegExp(r'[A-Z]').hasMatch(character)) return const Color(0xff1769aa);
    if (RegExp(r'[0-9]').hasMatch(character)) return const Color(0xffb45309);
    return const Color(0xffa23e48);
  }

  TextSpan _passwordSpan(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineMedium
        ?.copyWith(fontFamily: 'monospace', letterSpacing: 0);
    return TextSpan(
      children: _password
          .split('')
          .map(
            (character) => TextSpan(
              text: character,
              style: style?.copyWith(
                color: _characterColor(character, context),
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _openVault() => openVault(context);

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) =>
      CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: (next) {
          if (next != null) {
            onChanged(next);
            _regenerate();
          }
        },
        title: Text(label),
        controlAffinity: ListTileControlAffinity.leading,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: GestureDetector(
        onLongPress: _openVault,
        child: Text(tr(context, 'Password Generator', '密码生成器')),
      ),
      actions: [
        IconButton(
          tooltip: tr(context, 'Appearance and language', '外观和语言'),
          onPressed: () => showSettings(context),
          icon: const Icon(Icons.tune),
        ),
        IconButton(
          tooltip: tr(context, 'Reset defaults', '恢复默认设置'),
          onPressed: _resetDefaults,
          icon: const Icon(Icons.restart_alt),
        ),
        toolInfoAction(context, 'password-generator'),
      ],
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tr(context, 'Generated password', '生成的密码'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 18),
                      SelectableText.rich(
                        _passwordSpan(context),
                        textAlign: TextAlign.center,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _password.isEmpty
                                  ? null
                                  : () async {
                                      final copiedMessage = tr(
                                        context,
                                        'Password copied',
                                        '密码已复制',
                                      );
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      await Clipboard.setData(
                                        ClipboardData(text: _password),
                                      );
                                      if (!mounted) return;
                                      messenger.showSnackBar(
                                        SnackBar(content: Text(copiedMessage)),
                                      );
                                    },
                              icon: const Icon(Icons.copy),
                              label: Text(tr(context, 'Copy', '复制')),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            tooltip: tr(context, 'Generate', '生成'),
                            onPressed: _regenerate,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tr(context, 'Character filters', '字符筛选'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 520 ? 2 : 1;
                          return GridView(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisExtent: 48,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 2,
                                ),
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _check(
                                tr(context, 'Lowercase', '小写字母'),
                                _lowercase,
                                (value) => setState(() => _lowercase = value),
                              ),
                              _check(
                                tr(context, 'Uppercase', '大写字母'),
                                _uppercase,
                                (value) => setState(() => _uppercase = value),
                              ),
                              _check(
                                tr(context, 'Numbers', '数字'),
                                _numbers,
                                (value) => setState(() => _numbers = value),
                              ),
                              _check(
                                tr(context, 'Special characters', '特殊字符'),
                                _special,
                                (value) => setState(() => _special = value),
                              ),
                              _check(
                                tr(context, 'Unique characters', '唯一字符'),
                                _unique,
                                (value) => setState(() => _unique = value),
                              ),
                              _check(
                                tr(
                                  context,
                                  'Exclude ambiguous characters',
                                  '排除易混淆字符',
                                ),
                                _excludeAmbiguous,
                                (value) =>
                                    setState(() => _excludeAmbiguous = value),
                              ),
                              _check(
                                tr(
                                  context,
                                  'Highlight character types',
                                  '高亮字符类型',
                                ),
                                _highlight,
                                (value) => setState(() => _highlight = value),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Text('${tr(context, 'Length', '长度')}: $_length'),
                      Slider(
                        value: _length.toDouble(),
                        min: 8,
                        max: 64,
                        divisions: 56,
                        label: '$_length',
                        onChanged: (value) {
                          setState(() => _length = value.round());
                          _regenerate();
                        },
                      ),
                      if (_highlight) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 14,
                          runSpacing: 6,
                          children: [
                            _Legend(
                              label: tr(context, 'lowercase', '小写'),
                              color: Color(0xff13795b),
                            ),
                            _Legend(
                              label: tr(context, 'uppercase', '大写'),
                              color: Color(0xff1769aa),
                            ),
                            _Legend(
                              label: tr(context, 'numbers', '数字'),
                              color: Color(0xffb45309),
                            ),
                            _Legend(
                              label: tr(context, 'special', '特殊'),
                              color: Color(0xffa23e48),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        tr(context, 'Additional seed', '附加种子'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _seedController,
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        onChanged: (value) {
                          _seed = value;
                          _regenerate();
                        },
                        decoration: InputDecoration(
                          labelText: tr(
                            context,
                            'Enter your own seed',
                            '输入自定义种子',
                          ),
                          hintText: tr(
                            context,
                            'Optional text mixed into generation',
                            '可选，会参与密码生成',
                          ),
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr(
                          context,
                          'Or collect mouse / gesture movement',
                          '或采集鼠标 / 手势轨迹',
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      MouseRegion(
                        onHover: (details) => setState(
                          () => _addTracePoint(details.localPosition),
                        ),
                        onExit: (_) => _regenerate(),
                        child: RawGestureDetector(
                          // Touch input belongs to entropy collection instead
                          // of the ancestor scroll view for this pointer.
                          gestures: {
                            EagerGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  EagerGestureRecognizer
                                >(EagerGestureRecognizer.new, (_) {}),
                          },
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: (event) {
                              if (event.kind != PointerDeviceKind.mouse) {
                                setState(
                                  () => _addTracePoint(event.localPosition),
                                );
                              }
                            },
                            onPointerMove: (event) {
                              if (event.kind != PointerDeviceKind.mouse) {
                                setState(
                                  () => _addTracePoint(event.localPosition),
                                );
                              }
                            },
                            onPointerUp: (event) {
                              if (event.kind != PointerDeviceKind.mouse) {
                                _regenerate();
                              }
                            },
                            onPointerCancel: (event) {
                              if (event.kind != PointerDeviceKind.mouse) {
                                _regenerate();
                              }
                            },
                            child: Container(
                              height: 110,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: CustomPaint(
                                painter: _TracePainter(
                                  _trace,
                                  Theme.of(context).colorScheme.primary,
                                ),
                                child: Center(
                                  child: Text(
                                    _trace.isEmpty
                                        ? tr(
                                            context,
                                            'Move or drag here to collect movement',
                                            '在此移动或拖动以采集轨迹',
                                          )
                                        : '${_trace.length} ${tr(context, 'points collected', '个轨迹点')}',
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _trace.isEmpty
                              ? null
                              : () {
                                  setState(() => _trace.clear());
                                  _regenerate();
                                },
                          icon: const Icon(Icons.clear),
                          label: Text(tr(context, 'Clear movement', '清除轨迹')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TracePainter extends CustomPainter {
  const _TracePainter(this.points, this.color);
  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TracePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class PatternLock extends StatefulWidget {
  const PatternLock({
    super.key,
    required this.onCompleted,
    this.enabled = true,
  });

  final ValueChanged<List<int>> onCompleted;
  final bool enabled;

  @override
  State<PatternLock> createState() => _PatternLockState();
}

class _PatternLockState extends State<PatternLock> {
  static const _columns = 3;
  static const _dots = 9;
  static const _hitRadius = 26.0;

  final List<int> _selected = [];
  Offset? _pointer;

  Offset _center(int index, double size) {
    final step = size / _columns;
    return Offset(
      step * (index % _columns + 0.5),
      step * (index ~/ _columns + 0.5),
    );
  }

  int? _dotAt(Offset position, double size) {
    for (var index = 0; index < _dots; index++) {
      if ((_center(index, size) - position).distance <= _hitRadius) {
        return index;
      }
    }
    return null;
  }

  int? _between(int from, int to) {
    final fromX = from % _columns;
    final fromY = from ~/ _columns;
    final toX = to % _columns;
    final toY = to ~/ _columns;
    final deltaX = toX - fromX;
    final deltaY = toY - fromY;
    final aligned = deltaX == 0 || deltaY == 0 || deltaX.abs() == deltaY.abs();
    if (!aligned || (deltaX.abs() <= 1 && deltaY.abs() <= 1)) return null;
    if (deltaX.isOdd || deltaY.isOdd) return null;
    return ((fromY + toY) ~/ 2) * _columns + (fromX + toX) ~/ 2;
  }

  void _select(int index) {
    if (_selected.contains(index)) return;
    if (_selected.isNotEmpty) {
      final middle = _between(_selected.last, index);
      if (middle != null && !_selected.contains(middle)) _selected.add(middle);
    }
    _selected.add(index);
  }

  void _update(Offset position, double size) {
    final hit = _dotAt(position, size);
    setState(() {
      if (hit == null) {
        _pointer = position;
      } else {
        _select(hit);
        _pointer = _center(hit, size);
      }
    });
  }

  void _finish() {
    final result = List<int>.of(_selected);
    setState(() {
      _selected.clear();
      _pointer = null;
    });
    if (result.length >= 4) widget.onCompleted(result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          final centers = List<Offset>.generate(
            _dots,
            (index) => _center(index, size),
          );
          return GestureDetector(
            onPanStart: widget.enabled
                ? (details) => _update(details.localPosition, size)
                : null,
            onPanUpdate: widget.enabled
                ? (details) => _update(details.localPosition, size)
                : null,
            onPanEnd: widget.enabled ? (_) => _finish() : null,
            child: CustomPaint(
              size: Size.square(size),
              painter: _PatternPainter(
                centers: centers,
                selected: List<int>.of(_selected),
                pointer: _pointer,
                lineColor: scheme.primary,
                dotColor: scheme.outline,
                activeColor: scheme.primary,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  const _PatternPainter({
    required this.centers,
    required this.selected,
    required this.pointer,
    required this.lineColor,
    required this.dotColor,
    required this.activeColor,
  });

  final List<Offset> centers;
  final List<int> selected;
  final Offset? pointer;
  final Color lineColor;
  final Color dotColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    if (selected.length > 1) {
      final path = Path()
        ..moveTo(centers[selected.first].dx, centers[selected.first].dy);
      for (final index in selected.skip(1)) {
        path.lineTo(centers[index].dx, centers[index].dy);
      }
      canvas.drawPath(path, line);
    }
    if (selected.isNotEmpty && pointer != null) {
      canvas.drawLine(centers[selected.last], pointer!, line);
    }
    final halo = Paint()..color = activeColor.withValues(alpha: 0.18);
    final active = Paint()..color = activeColor;
    final idle = Paint()
      ..color = dotColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (var index = 0; index < centers.length; index++) {
      final center = centers[index];
      if (selected.contains(index)) {
        canvas.drawCircle(center, 22, halo);
        canvas.drawCircle(center, 10, active);
      } else {
        canvas.drawCircle(center, 10, idle);
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter oldDelegate) =>
      oldDelegate.selected != selected ||
      oldDelegate.pointer != pointer ||
      oldDelegate.lineColor != lineColor;
}

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.store});
  final VaultStore store;
  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pin = TextEditingController();
  VaultLockType _setupType = VaultLockType.pattern;
  String? _firstSecret;
  bool _busy = false;
  String? _error;
  int _patternAttempt = 0;

  bool get _creating => !widget.store.exists;
  VaultLockType get _type =>
      _creating ? _setupType : (widget.store.lockType ?? VaultLockType.pattern);
  bool get _confirming => _creating && _firstSecret != null;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  String get _instruction {
    if (!_creating) {
      return _type == VaultLockType.pattern
          ? tr(context, 'Draw your pattern to unlock.', '绘制图案以解锁。')
          : tr(context, 'Enter your PIN to unlock.', '输入 PIN 以解锁。');
    }
    if (_confirming) {
      return _type == VaultLockType.pattern
          ? tr(context, 'Draw the pattern again to confirm.', '再次绘制图案以确认。')
          : tr(context, 'Enter the PIN again to confirm.', '再次输入 PIN 以确认。');
    }
    return _type == VaultLockType.pattern
        ? tr(
            context,
            'Draw a pattern to protect your private notes.',
            '绘制图案以保护你的私密笔记。',
          )
        : tr(
            context,
            'Choose a PIN (4-8 digits) for your private notes.',
            '设置 PIN 密码（4-8 位数字）保护私密笔记。',
          );
  }

  String? _validate(String secret) {
    if (_type != VaultLockType.pin) return null;
    if (secret.length < 4) {
      return tr(context, 'Use at least 4 digits.', '至少使用 4 位数字。');
    }
    if (secret.length > 8) {
      return tr(context, 'Use at most 8 digits.', '最多使用 8 位数字。');
    }
    return null;
  }

  Future<void> _submit(String secret) async {
    if (_busy) return;
    final error = _validate(secret);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_creating) {
      await _create(secret);
    } else {
      await _unlock(secret);
    }
  }

  Future<void> _create(String secret) async {
    if (_firstSecret == null) {
      setState(() {
        _firstSecret = secret;
        _error = null;
        _pin.clear();
        _patternAttempt++;
      });
      return;
    }
    if (_firstSecret != secret) {
      setState(() {
        _firstSecret = null;
        _error = tr(
          context,
          'Entries did not match. Try again.',
          '两次输入不一致，请重试。',
        );
        _pin.clear();
        _patternAttempt++;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.create(type: _type, secret: secret);
      if (mounted) _openNotes();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(context, 'Unable to create the vault.', '无法创建保险库。'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock(String secret) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await widget.store.unlock(secret);
      if (!mounted) return;
      if (ok) {
        _openNotes();
      } else {
        setState(() {
          _error = tr(context, 'Wrong pattern or PIN.', '图案或 PIN 不正确。');
          _pin.clear();
          _patternAttempt++;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr(context, 'Unable to unlock.', '无法解锁。'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openNotes() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => NotesScreen(store: widget.store)),
    );
  }

  Widget _secretInput(BuildContext context) {
    if (_type == VaultLockType.pattern) {
      return PatternLock(
        key: ValueKey('pattern-$_patternAttempt'),
        enabled: !_busy,
        onCompleted: (pattern) => _submit(pattern.join('-')),
      );
    }
    return TextField(
      controller: _pin,
      autofocus: true,
      enabled: !_busy,
      obscureText: true,
      keyboardType: TextInputType.number,
      maxLength: 8,
      onSubmitted: _submit,
      decoration: InputDecoration(
        labelText: tr(context, 'PIN', 'PIN'),
        counterText: '',
        errorText: _error,
        border: const OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _creating
              ? tr(context, 'Create vault', '创建保险库')
              : tr(context, 'Unlock vault', '解锁保险库'),
        ),
        actions: [
          IconButton(
            tooltip: tr(context, 'Appearance and language', '外观和语言'),
            icon: const Icon(Icons.tune),
            onPressed: () => showSettings(context),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_creating && !_confirming) ...[
                  SegmentedButton<VaultLockType>(
                    segments: [
                      ButtonSegment(
                        value: VaultLockType.pattern,
                        label: Text(tr(context, 'Pattern', '九宫格')),
                        icon: const Icon(Icons.gesture),
                      ),
                      ButtonSegment(
                        value: VaultLockType.pin,
                        label: Text(tr(context, 'PIN', '数字 PIN')),
                        icon: const Icon(Icons.dialpad),
                      ),
                    ],
                    selected: {_setupType},
                    onSelectionChanged: _busy
                        ? null
                        : (selection) => setState(() {
                            _setupType = selection.first;
                            _error = null;
                            _pin.clear();
                            _patternAttempt++;
                          }),
                  ),
                  const SizedBox(height: 20),
                ],
                Text(_instruction, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                if (_type == VaultLockType.pattern)
                  Center(
                    child: SizedBox(width: 260, child: _secretInput(context)),
                  )
                else
                  _secretInput(context),
                if (_type == VaultLockType.pattern && _error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_type == VaultLockType.pin) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : () => _submit(_pin.text),
                    child: Text(
                      _creating
                          ? tr(context, 'Continue', '继续')
                          : tr(context, 'Unlock', '解锁'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.store});
  final VaultStore store;
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  Future<void> _edit([VaultNote? note]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditorScreen(store: widget.store, note: note),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'Private notes', '私密笔记')),
      actions: [
        IconButton(
          tooltip: tr(context, 'Appearance and language', '外观和语言'),
          icon: const Icon(Icons.tune),
          onPressed: () => showSettings(context),
        ),
        IconButton(
          tooltip: tr(context, 'Lock', '锁定'),
          icon: const Icon(Icons.lock),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
    body: widget.store.notes.isEmpty
        ? Center(child: Text(tr(context, 'No notes yet', '还没有笔记')))
        : ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: widget.store.notes.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (_, index) {
              final note = widget.store.notes[index];
              return ListTile(
                title: Text(
                  note.title.isEmpty
                      ? tr(context, 'Untitled', '未命名')
                      : note.title,
                ),
                subtitle: Text(
                  note.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: note.images.isNotEmpty
                    ? const Icon(Icons.image_outlined)
                    : null,
                onTap: () => _edit(note),
              );
            },
          ),
    floatingActionButton: FloatingActionButton(
      onPressed: _edit,
      tooltip: tr(context, 'New note', '新建笔记'),
      child: const Icon(Icons.add),
    ),
  );
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.store, this.note});
  final VaultStore store;
  final VaultNote? note;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _title = TextEditingController(
    text: widget.note?.title ?? '',
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.note?.body ?? '',
  );
  late final List<String> _images = List.of(widget.note?.images ?? []);
  bool _saving = false;
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _image() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isNotEmpty) {
      final bytes = await files.first.readAsBytes();
      if (mounted) setState(() => _images.add(base64Encode(bytes)));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final note =
        widget.note ??
        VaultNote(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: '',
          body: '',
          updatedAt: DateTime.now(),
        );
    note.title = _title.text;
    note.body = _body.text;
    note.images = _images;
    note.updatedAt = DateTime.now();
    if (widget.note == null) widget.store.notes.insert(0, note);
    await widget.store.save();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'Note', '笔记')),
      actions: [
        IconButton(
          tooltip: tr(context, 'Add image', '添加图片'),
          icon: const Icon(Icons.image_outlined),
          onPressed: _image,
        ),
        IconButton(
          tooltip: tr(context, 'Save', '保存'),
          icon: const Icon(Icons.save_outlined),
          onPressed: _saving ? null : _save,
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(
              hintText: tr(context, 'Title', '标题'),
              border: InputBorder.none,
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Expanded(
            child: TextField(
              controller: _body,
              expands: true,
              maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: tr(context, 'Write privately...', '在这里私密记录...'),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_images.isNotEmpty)
            SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _images
                    .map(
                      (image) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Image.memory(
                          base64Decode(image),
                          width: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    ),
  );
}
