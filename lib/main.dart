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
import 'package:flutter_soloud/flutter_soloud.dart';
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
    'tone-generator' => const ToneGeneratorScreen(),
    'speaker-cleaner' => const SpeakerCleanerScreen(),
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
        IconButton(
          tooltip: tr(context, 'Acknowledgements', '致谢'),
          onPressed: () => showToolAcknowledgements(
            context,
            toolInfoById('tone-generator')!,
          ),
          icon: const Icon(Icons.info_outline),
        ),
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
