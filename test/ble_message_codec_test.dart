import 'dart:convert';
import 'dart:typed_data';

import 'package:clipboard_share/services/ble_message_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encode single chunk for small JSON', () {
    final chunks = BleMessageCodec.encode('{"type":"auth"}');
    expect(chunks.length, 1);
    expect(utf8.decode(chunks.first), '{"type":"auth"}');
  });

  test('encode and decode multi chunk message', () {
    final payload = 'x' * 900;
    final original = jsonEncode({'type': 'clipboard', 'content': payload});
    final chunks = BleMessageCodec.encode(original);

    expect(chunks.length, greaterThan(1));

    final assembly = <int, String>{};
    String? decoded;
    for (final chunk in chunks) {
      decoded = BleMessageCodec.decodeChunk(chunk, assembly: assembly);
    }
    expect(decoded, original);
  });
}
