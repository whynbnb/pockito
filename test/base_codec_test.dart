import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:privacy_vault/main.dart';

void main() {
  test('base codecs match known vectors', () {
    final hello = utf8.encode('Hello');

    expect(BaseCodec.encode(BaseVariant.base16, hello), '48656c6c6f');
    expect(BaseCodec.encode(BaseVariant.base32, hello), 'JBSWY3DP');
    expect(BaseCodec.encode(BaseVariant.base64, hello), 'SGVsbG8=');
    expect(BaseCodec.encode(BaseVariant.base16, const [0]), '00');
    expect(BaseCodec.encode(BaseVariant.base58, const [0]), '1');
    expect(BaseCodec.encode(BaseVariant.base58, const [1]), '2');
    expect(BaseCodec.encode(BaseVariant.base58, const [0, 1]), '12');
  });

  test('base codecs round-trip arbitrary bytes', () {
    final bytes = List<int>.generate(64, (index) => (index * 37 + 11) & 0xff);
    for (final variant in BaseVariant.values) {
      final encoded = BaseCodec.encode(variant, bytes);
      expect(BaseCodec.decode(variant, encoded), bytes, reason: '$variant');
    }
  });

  test('base58 preserves leading zero bytes', () {
    const bytes = [0, 0, 1, 2, 3, 250];
    final encoded = BaseCodec.encode(BaseVariant.base58, bytes);
    expect(BaseCodec.decode(BaseVariant.base58, encoded), bytes);
  });

  test('invalid input throws a FormatException', () {
    expect(
      () => BaseCodec.decode(BaseVariant.base16, 'xyz'),
      throwsFormatException,
    );
    expect(
      () => BaseCodec.decode(BaseVariant.base32, '1'),
      throwsFormatException,
    );
    expect(
      () => BaseCodec.decode(BaseVariant.base58, '0'),
      throwsFormatException,
    );
  });
}
