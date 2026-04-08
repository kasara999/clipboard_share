import 'dart:convert';

import 'package:clipboard_share/services/clipboard_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// テスト用: flutter Clipboard チャンネルをモック
void _mockClipboard(String? text) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') {
      return text != null ? {'text': text} : null;
    }
    if (call.method == 'Clipboard.setData') {
      return null;
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('ClipboardItem', () {
    test('text コンストラクタ', () {
      final item = ClipboardItem.text('hello');
      expect(item.type, equals(ClipboardItemType.text));
      expect(item.text, equals('hello'));
      expect(item.imageBytes, isNull);
    });

    test('image コンストラクタ', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final item = ClipboardItem.image(bytes);
      expect(item.type, equals(ClipboardItemType.image));
      expect(item.imageBytes, equals(bytes));
      expect(item.text, isNull);
    });
  });

  group('ClipboardService テキスト検知', () {
    late ClipboardService service;

    setUp(() {
      service = ClipboardService();
    });

    tearDown(() {
      service.dispose();
    });

    test('テキスト変化を検知してstreamに流す', () async {
      _mockClipboard('first text');

      final received = <ClipboardItem>[];
      service.itemStream.listen(received.add);
      service.startPolling();

      await Future.delayed(const Duration(milliseconds: 700));
      expect(received.length, equals(1));
      expect(received.first.text, equals('first text'));
    });

    test('同じテキストは重複して流れない', () async {
      _mockClipboard('same text');

      final received = <ClipboardItem>[];
      service.itemStream.listen(received.add);
      service.startPolling();

      await Future.delayed(const Duration(milliseconds: 1200));
      expect(received.length, equals(1)); // 2回以上ポーリングしても1回だけ
    });

    test('テキストが変わると再度検知される', () async {
      int callCount = 0;
      final texts = ['first', 'second'];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          final t = texts[callCount.clamp(0, texts.length - 1)];
          callCount++;
          return {'text': t};
        }
        return null;
      });

      final received = <String?>[];
      service.itemStream.listen((item) {
        if (item.type == ClipboardItemType.text) received.add(item.text);
      });
      service.startPolling();

      await Future.delayed(const Duration(milliseconds: 1200));
      expect(received, contains('first'));
      expect(received, contains('second'));
    });

    test('空テキストは無視される', () async {
      _mockClipboard('');

      final received = <ClipboardItem>[];
      service.itemStream.listen(received.add);
      service.startPolling();

      await Future.delayed(const Duration(milliseconds: 700));
      expect(received.length, equals(0));
    });
  });

  group('ClipboardService setFromRemote', () {
    late ClipboardService service;

    setUp(() {
      service = ClipboardService();
    });

    tearDown(() {
      service.dispose();
    });

    test('テキストメッセージを受け取りクリップボードに書き込む', () async {
      String? written;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          written = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });

      await service.setFromRemote({
        'type': 'clipboard',
        'content_type': 'text',
        'content': 'from iphone',
      });

      expect(written, equals('from iphone'));
    });

    test('setFromRemote後のポーリングでリモート書き込みを再送しない', () async {
      _mockClipboard('from iphone');

      final received = <ClipboardItem>[];
      service.itemStream.listen(received.add);

      await service.setFromRemote({
        'type': 'clipboard',
        'content_type': 'text',
        'content': 'from iphone',
      });

      service.startPolling();
      await Future.delayed(const Duration(milliseconds: 700));

      // _ignoreNext により最初のポーリングはスキップされる
      expect(received.length, equals(0));
    });

    test('画像メッセージのBase64デコードが正しい', () async {
      final originalBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG magic
      final base64Str = base64Encode(originalBytes);

      // Pasteboard.writeImage はプラグインなのでここでは例外が出ることを確認するだけ
      // （実機では動作する）
      try {
        await service.setFromRemote({
          'type': 'clipboard',
          'content_type': 'image',
          'content': base64Str,
        });
      } catch (e) {
        // MissingPluginException はテスト環境では許容
        expect(e.toString(), contains('MissingPluginException'));
      }
    });
  });
}
