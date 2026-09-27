import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pinyin/pinyin.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

class LocalPreferences {
  LocalPreferences([this._directory]);
  static const _fileName = 'tool_prefs.json';
  final Directory? _directory;
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

class AppSettings extends ChangeNotifier {
  AppSettings({LocalPreferences? preferences})
    : _preferences = preferences ?? LocalPreferences();
  final LocalPreferences _preferences;
  ThemeMode themeMode = ThemeMode.system;
  LocaleMode localeMode = LocaleMode.system;

  static AppSettings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SettingsScope>()!.settings;

  Future<void> load() async {
    try {
      final theme = await _preferences.getString('ui_theme');
      final language = await _preferences.getString('ui_language');
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
      notifyListeners();
    } catch (_) {
      // Keep defaults when local storage is unavailable.
    }
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
  const VaultApp({super.key});

  @override
  State<VaultApp> createState() => _VaultAppState();
}

class _VaultAppState extends State<VaultApp> {
  final _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    _settings.load();
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
      builder: (context, _) => MaterialApp(
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
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff007c72)),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff54c7bb),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    ),
  );
}

Future<void> showSettings(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (context) {
    final settings = AppSettings.of(context);
    return SafeArea(
      child: Padding(
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
              onSelectionChanged: (selection) =>
                  settings.setTheme(selection.first),
            ),
            const SizedBox(height: 4),
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
              onSelectionChanged: (selection) =>
                  settings.setLocaleMode(selection.first),
            ),
          ],
        ),
      ),
    );
  },
);

class ToolCredit {
  const ToolCredit({
    required this.project,
    required this.author,
    required this.license,
    required this.url,
  });

  final String project;
  final String author;
  final String license;
  final String url;
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
];

ToolInfo? toolInfoById(String id) {
  for (final tool in toolInfos) {
    if (tool.id == id) return tool;
  }
  return null;
}

String toolCreditDescription(
  BuildContext context,
  ToolInfo tool,
  ToolCredit credit,
) => tr(
  context,
  'The ${tool.englishTitle} tool is inspired by the open-source '
      '${credit.project} by ${credit.author}.',
  '${tool.chineseTitle}的界面与思路灵感来自 ${credit.author} 的开源项目 '
      '${credit.project}。',
);

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

Future<void> showToolAcknowledgements(BuildContext context, ToolInfo tool) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(context, 'Acknowledgements', '致谢')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!tool.hasAcknowledgements)
                Text(
                  tr(
                    context,
                    'No acknowledgements for this tool.',
                    '此工具没有需要标记的致谢信息。',
                  ),
                ),
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
              if (tool.englishNote.isNotEmpty) ...[
                const Divider(height: 24),
                Text(
                  tr(context, tool.englishNote, tool.chineseNote),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(context, 'Close', '关闭')),
          ),
        ],
      ),
    );

Future<void> openVault(BuildContext context) async {
  final store = VaultStore();
  await store.initialize();
  if (!context.mounted) return;
  await Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => UnlockScreen(store: store)));
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
    _ => null,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: GestureDetector(
        onLongPress: () => openVault(context),
        child: Text(tr(context, 'Pockito', '妙物袋')),
      ),
      actions: [
        IconButton(
          tooltip: tr(context, 'Appearance and language', '外观和语言'),
          onPressed: () => showSettings(context),
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          children: [
            for (final tool in toolInfos) ...[
              _ToolTile(
                icon: tool.icon,
                title: tr(context, tool.englishTitle, tool.chineseTitle),
                subtitle: tr(
                  context,
                  tool.englishSubtitle,
                  tool.chineseSubtitle,
                ),
                onTap: () {
                  final screen = _screenFor(tool.id);
                  if (screen != null) _open(context, screen);
                },
              ),
              if (tool != toolInfos.last) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        child: Icon(icon),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
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
        actions: [
          IconButton(
            tooltip: tr(context, 'Acknowledgements', '致谢'),
            onPressed: () =>
                showToolAcknowledgements(context, toolInfoById('counter')!),
            icon: const Icon(Icons.info_outline),
          ),
        ],
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
          IconButton(
            tooltip: tr(context, 'Acknowledgements', '致谢'),
            onPressed: () => showToolAcknowledgements(
              context,
              toolInfoById('game-counter')!,
            ),
            icon: const Icon(Icons.info_outline),
          ),
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
      appBar: AppBar(title: Text(tr(context, 'Basexx', 'Base 编解码'))),
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
        IconButton(
          tooltip: tr(context, 'Acknowledgements', '致谢'),
          onPressed: () =>
              showToolAcknowledgements(context, toolInfoById('tic-tac-toe')!),
          icon: const Icon(Icons.info_outline),
        ),
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
        IconButton(
          tooltip: tr(context, 'Acknowledgements', '致谢'),
          onPressed: () =>
              showToolAcknowledgements(context, toolInfoById('flashlight')!),
          icon: const Icon(Icons.info_outline),
        ),
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
        IconButton(
          tooltip: tr(context, 'Acknowledgements', '致谢'),
          onPressed: () =>
              showToolAcknowledgements(context, toolInfoById('vibrator')!),
          icon: const Icon(Icons.info_outline),
        ),
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

class VaultStore {
  static const _format = 'PVLT1';
  static const _iterations = 210000;
  final _cipher = AesGcm.with256bits();
  final _random = Random.secure();
  final _storage = const FlutterSecureStorage();
  late File _file;
  List<VaultNote> notes = [];
  SecretKey? _dataKey;

  Future<void> initialize() async {
    final directory = await getApplicationSupportDirectory();
    _file = File(
      '${directory.path}${Platform.pathSeparator}pockito-cache.pvlt',
    );
    await _recoverInterruptedWrite();
  }

  Future<bool> _isValidEnvelope(File candidate) async {
    try {
      final value = jsonDecode(await candidate.readAsString());
      if (value is! Map<String, dynamic> ||
          value['format'] != _format ||
          value['slots'] is! Map ||
          value['payload'] is! Map) {
        return false;
      }
      final slots = Map<String, dynamic>.from(value['slots'] as Map);
      final payload = Map<String, dynamic>.from(value['payload'] as Map);
      for (final slot in [slots['password'], slots['recovery']]) {
        final fields = Map<String, dynamic>.from(slot as Map);
        _decode(fields['salt'] as String);
        _decode(fields['nonce'] as String);
        _decode(fields['ciphertext'] as String);
        _decode(fields['mac'] as String);
      }
      _decode(payload['nonce'] as String);
      _decode(payload['ciphertext'] as String);
      _decode(payload['mac'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _recoverInterruptedWrite() async {
    final temporary = File('${_file.path}.writing');
    final backup = File('${_file.path}.backup');
    final mainExists = await _file.exists();
    final mainValid = mainExists && await _isValidEnvelope(_file);

    if (!mainValid && await _isValidEnvelope(temporary)) {
      if (mainExists) await _file.delete();
      await temporary.rename(_file.path);
    } else if (!mainValid && await _isValidEnvelope(backup)) {
      if (mainExists) await _file.delete();
      await backup.rename(_file.path);
    }
    if (await temporary.exists()) await temporary.delete();
    if (await backup.exists()) await backup.delete();
  }

  bool get exists => _file.existsSync();

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

  Future<Map<String, String>> _wrap(SecretKey key, String secret) async {
    final salt = _bytes(16);
    final wrappingKey = await _derive(secret, salt);
    final box = await _cipher.encrypt(
      await key.extractBytes(),
      secretKey: wrappingKey,
      nonce: _bytes(12),
    );
    return {
      'salt': _encode(salt),
      'nonce': _encode(box.nonce),
      'ciphertext': _encode(box.cipherText),
      'mac': _encode(box.mac.bytes),
    };
  }

  Future<SecretKey> _unwrap(Map<String, dynamic> slot, String secret) async {
    final wrappingKey = await _derive(secret, _decode(slot['salt'] as String));
    final bytes = await _cipher.decrypt(
      SecretBox(
        _decode(slot['ciphertext'] as String),
        nonce: _decode(slot['nonce'] as String),
        mac: Mac(_decode(slot['mac'] as String)),
      ),
      secretKey: wrappingKey,
    );
    return SecretKey(bytes);
  }

  Future<String> create(String password) async {
    _dataKey = SecretKey(_bytes(32));
    final recovery = List<String>.generate(
      4,
      (_) =>
          _encode(_bytes(5)).replaceAll('-', '').substring(0, 7).toUpperCase(),
    ).join('-');
    final passwordSlot = await _wrap(_dataKey!, password);
    final recoverySlot = await _wrap(_dataKey!, recovery);
    notes = [];
    await _write({'password': passwordSlot, 'recovery': recoverySlot});
    try {
      await _storage.write(
        key: 'vault_biometric_key',
        value: _encode(await _dataKey!.extractBytes()),
      );
    } catch (_) {
      // The vault remains usable with its password and recovery key.
    }
    return recovery;
  }

  Future<void> unlockWithPassword(String password) async {
    final envelope = await _readEnvelope();
    _dataKey = await _unwrap(
      Map<String, dynamic>.from(envelope['slots']['password'] as Map),
      password,
    );
    await _loadPayload(envelope);
  }

  Future<void> unlockWithRecovery(String code) async {
    final envelope = await _readEnvelope();
    _dataKey = await _unwrap(
      Map<String, dynamic>.from(envelope['slots']['recovery'] as Map),
      code.trim().toUpperCase(),
    );
    await _loadPayload(envelope);
  }

  Future<bool> unlockWithBiometrics() async {
    final available = await LocalAuthentication().canCheckBiometrics;
    if (!available ||
        !await LocalAuthentication().authenticate(
          localizedReason: 'Unlock your private notes',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        )) {
      return false;
    }
    final encoded = await _storage.read(key: 'vault_biometric_key');
    if (encoded == null) {
      return false;
    }
    _dataKey = SecretKey(_decode(encoded));
    await _loadPayload(await _readEnvelope());
    return true;
  }

  Future<Map<String, dynamic>> _readEnvelope() async {
    final decoded =
        jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    if (decoded['format'] != _format) {
      throw const FormatException('Unsupported vault format');
    }
    return decoded;
  }

  Future<void> _loadPayload(Map<String, dynamic> envelope) async {
    final payload = Map<String, dynamic>.from(envelope['payload'] as Map);
    final plain = await _cipher.decrypt(
      SecretBox(
        _decode(payload['ciphertext'] as String),
        nonce: _decode(payload['nonce'] as String),
        mac: Mac(_decode(payload['mac'] as String)),
      ),
      secretKey: _dataKey!,
    );
    final json = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    notes = (json['notes'] as List? ?? [])
        .map(
          (item) => VaultNote.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }

  Future<void> save() async {
    final old = await _readEnvelope();
    await _write(Map<String, dynamic>.from(old['slots'] as Map));
  }

  Future<void> _write(Map<String, dynamic> slots) async {
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
      'version': 1,
      'slots': slots,
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
        IconButton(
          tooltip: tr(context, 'Acknowledgements', '致谢'),
          onPressed: () => showToolAcknowledgements(
            context,
            toolInfoById('password-generator')!,
          ),
          icon: const Icon(Icons.info_outline),
        ),
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

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.store});
  final VaultStore store;
  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _secret = TextEditingController();
  bool _recovery = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_secret.text.isEmpty) return;
    final creating = !widget.store.exists;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!widget.store.exists) {
        final recovery = await widget.store.create(_secret.text);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr(context, 'Recovery key', '恢复密钥')),
            content: SelectableText(
              '${tr(context, 'Store this offline. It can unlock this vault if your password is lost.', '请离线保存。忘记主密码时，它可以解锁此保险库。')}\n\n$recovery',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr(context, 'I stored it', '我已保存')),
              ),
            ],
          ),
        );
      } else if (_recovery) {
        await widget.store.unlockWithRecovery(_secret.text);
      } else {
        await widget.store.unlockWithPassword(_secret.text);
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => NotesScreen(store: widget.store)),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = creating
              ? tr(
                  context,
                  'Unable to create the encrypted vault. Check secure storage permissions and try again.',
                  '无法创建加密保险库，请检查安全存储权限后重试。',
                )
              : tr(
                  context,
                  'Unable to unlock. Check the credential and try again.',
                  '无法解锁，请检查凭据后重试。',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _biometric() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await widget.store.unlockWithBiometrics()) {
        throw StateError('Not available');
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => NotesScreen(store: widget.store)),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = tr(
            context,
            'Biometric unlock is not available on this device.',
            '此设备无法使用生物识别解锁。',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creating = !widget.store.exists;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          creating
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
                Text(
                  creating
                      ? tr(
                          context,
                          'Create a strong master password. Your notes never leave this device.',
                          '创建一个强主密码。你的笔记不会离开此设备。',
                        )
                      : (_recovery
                            ? tr(
                                context,
                                'Enter the recovery key from your offline copy.',
                                '请输入你离线保存的恢复密钥。',
                              )
                            : tr(
                                context,
                                'Enter your master password.',
                                '请输入主密码。',
                              )),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _secret,
                  autofocus: true,
                  obscureText: !_recovery,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: _recovery
                        ? tr(context, 'Recovery key', '恢复密钥')
                        : tr(context, 'Master password', '主密码'),
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(
                    creating
                        ? tr(context, 'Create encrypted vault', '创建加密保险库')
                        : tr(context, 'Unlock', '解锁'),
                  ),
                ),
                if (!creating) ...[
                  TextButton.icon(
                    onPressed: _busy ? null : _biometric,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(tr(context, 'Use biometrics', '使用生物识别')),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _recovery = !_recovery;
                      _error = null;
                      _secret.clear();
                    }),
                    child: Text(
                      _recovery
                          ? tr(context, 'Use master password', '使用主密码')
                          : tr(
                              context,
                              'Use security key / recovery key',
                              '使用安全密钥 / 恢复密钥',
                            ),
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
