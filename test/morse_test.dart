import 'package:flutter_test/flutter_test.dart';
import 'package:pockito/main.dart';

void main() {
  test('morse encodes letters, numbers and word gaps', () {
    expect(textToMorse('SOS'), '... --- ...');
    expect(textToMorse('Hi 07'), '.... .. / ----- --...');
  });

  test('morse converts Chinese characters to pinyin', () {
    expect(textToMorse('你好'), '-. .. .... .- ---');
  });

  test('morse skips unsupported characters', () {
    expect(textToMorse('a!b'), '.- -...');
    expect(textToMorse('   '), '');
  });

  test('morse blink pattern follows standard timing', () {
    expect(morseBlinkPattern('... --- ...', unit: 200), [
      200,
      200,
      200,
      200,
      200,
      600,
      600,
      200,
      600,
      200,
      600,
      600,
      200,
      200,
      200,
      200,
      200,
    ]);
    expect(morseBlinkPattern('', unit: 200), isEmpty);
  });
}
