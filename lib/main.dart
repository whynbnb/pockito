import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VaultApp());
}

class VaultApp extends StatelessWidget {
  const VaultApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Utility Kit',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff007c72)),
      useMaterial3: true,
    ),
    home: const GeneratorScreen(),
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
      '${directory.path}${Platform.pathSeparator}utility-cache.pvlt',
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

class _GeneratorScreenState extends State<GeneratorScreen>
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    _password = _makePassword();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // macOS can lose modifier-key state while the window is unfocused.
      unawaited(HardwareKeyboard.instance.syncKeyboardState());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        _error = 'Select at least one character type.';
      });
      return;
    }
    if (_unique && _length > _pool.length) {
      setState(() {
        _password = '';
        _error =
            'Unique mode supports up to ${_pool.length} characters with the current filters.';
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

  Future<void> _openVault() async {
    final store = VaultStore();
    await store.initialize();
    if (!mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => UnlockScreen(store: store)));
  }

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
        child: const Text('Password Generator'),
      ),
      actions: [
        IconButton(
          tooltip: 'Reset defaults',
          onPressed: _resetDefaults,
          icon: const Icon(Icons.restart_alt),
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
                        'Generated password',
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
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      await Clipboard.setData(
                                        ClipboardData(text: _password),
                                      );
                                      if (!mounted) return;
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text('Password copied'),
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            tooltip: 'Generate',
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
                        'Character filters',
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
                                'Lowercase',
                                _lowercase,
                                (value) => setState(() => _lowercase = value),
                              ),
                              _check(
                                'Uppercase',
                                _uppercase,
                                (value) => setState(() => _uppercase = value),
                              ),
                              _check(
                                'Numbers',
                                _numbers,
                                (value) => setState(() => _numbers = value),
                              ),
                              _check(
                                'Special characters',
                                _special,
                                (value) => setState(() => _special = value),
                              ),
                              _check(
                                'Unique characters',
                                _unique,
                                (value) => setState(() => _unique = value),
                              ),
                              _check(
                                'Exclude ambiguous characters',
                                _excludeAmbiguous,
                                (value) =>
                                    setState(() => _excludeAmbiguous = value),
                              ),
                              _check(
                                'Highlight character types',
                                _highlight,
                                (value) => setState(() => _highlight = value),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Text('Length: $_length'),
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
                          children: const [
                            _Legend(
                              label: 'lowercase',
                              color: Color(0xff13795b),
                            ),
                            _Legend(
                              label: 'uppercase',
                              color: Color(0xff1769aa),
                            ),
                            _Legend(label: 'numbers', color: Color(0xffb45309)),
                            _Legend(label: 'special', color: Color(0xffa23e48)),
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
                        'Additional seed',
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
                        decoration: const InputDecoration(
                          labelText: 'Enter your own seed',
                          hintText: 'Optional text mixed into generation',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Or collect mouse / gesture movement',
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
                                        ? 'Move or drag here to collect movement'
                                        : '${_trace.length} points collected',
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
                          label: const Text('Clear movement'),
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
            title: const Text('Recovery key'),
            content: SelectableText(
              'Store this offline. It can unlock this vault if your password is lost.\n\n$recovery',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('I stored it'),
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
              ? 'Unable to create the encrypted vault. Check secure storage permissions and try again.'
              : 'Unable to unlock. Check the credential and try again.',
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
          () => _error = 'Biometric unlock is not available on this device.',
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
      appBar: AppBar(title: Text(creating ? 'Create vault' : 'Unlock vault')),
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
                      ? 'Create a strong master password. Your notes never leave this device.'
                      : (_recovery
                            ? 'Enter the recovery key from your offline copy.'
                            : 'Enter your master password.'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _secret,
                  autofocus: true,
                  obscureText: !_recovery,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: _recovery ? 'Recovery key' : 'Master password',
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(creating ? 'Create encrypted vault' : 'Unlock'),
                ),
                if (!creating) ...[
                  TextButton.icon(
                    onPressed: _busy ? null : _biometric,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Use biometrics'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _recovery = !_recovery;
                      _error = null;
                      _secret.clear();
                    }),
                    child: Text(
                      _recovery
                          ? 'Use master password'
                          : 'Use security key / recovery key',
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
      title: const Text('Private notes'),
      actions: [
        IconButton(
          tooltip: 'Lock',
          icon: const Icon(Icons.lock),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
    body: widget.store.notes.isEmpty
        ? const Center(child: Text('No notes yet'))
        : ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: widget.store.notes.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (_, index) {
              final note = widget.store.notes[index];
              return ListTile(
                title: Text(note.title.isEmpty ? 'Untitled' : note.title),
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
      tooltip: 'New note',
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
      title: const Text('Note'),
      actions: [
        IconButton(
          tooltip: 'Add image',
          icon: const Icon(Icons.image_outlined),
          onPressed: _image,
        ),
        IconButton(
          tooltip: 'Save',
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
            decoration: const InputDecoration(
              hintText: 'Title',
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
              decoration: const InputDecoration(
                hintText: 'Write privately...',
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
