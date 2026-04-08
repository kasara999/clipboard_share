import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipboard_share/services/token_service.dart';
import 'package:clipboard_share/services/websocket_server.dart';
import 'package:test/test.dart';

const _testPort = 18765;

Future<WebSocket> connectAndAuth({bool useValidToken = true}) async {
  final socket = await WebSocket.connect('ws://localhost:$_testPort');
  final token = useValidToken ? TokenService.token : 'invalid-token';
  socket.add(jsonEncode({'type': 'auth', 'token': token}));
  return socket;
}

void main() {
  late WebSocketServer server;

  setUp(() async {
    server = WebSocketServer(port: _testPort);
    await server.start();
  });

  tearDown(() async {
    await server.stop();
  });

  test('サーバーがポート8765で起動する', () async {
    // 接続できればOK
    final socket = await WebSocket.connect('ws://localhost:$_testPort');
    expect(socket.readyState, equals(WebSocket.open));
    await socket.close();
  });

  test('正しいトークンで認証成功', () async {
    final socket = await connectAndAuth(useValidToken: true);
    final response = await socket.first.timeout(const Duration(seconds: 2));
    final msg = jsonDecode(response as String) as Map<String, dynamic>;
    expect(msg['type'], equals('auth_ok'));
    await socket.close();
  });

  test('不正なトークンで認証拒否・切断される', () async {
    final socket = await connectAndAuth(useValidToken: false);
    final msgs = <dynamic>[];
    await for (final m in socket.timeout(const Duration(seconds: 2))) {
      msgs.add(m);
    }
    expect(msgs.length, equals(1));
    final msg = jsonDecode(msgs.first as String) as Map<String, dynamic>;
    expect(msg['type'], equals('auth_error'));
  });

  test('認証後にメッセージをbroadcastできる', () async {
    // s2の受信バッファを先に用意
    final s2 = await connectAndAuth();
    final s2Messages = <Map<String, dynamic>>[];
    final s2Done = Completer<void>();
    s2.listen(
      (data) => s2Messages.add(jsonDecode(data as String) as Map<String, dynamic>),
      onDone: () => s2Done.complete(),
    );

    final s1 = await connectAndAuth();
    await s1.first; // auth_ok

    // auth_ok が届くまで待つ
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 50));
      return s2Messages.isEmpty;
    }).timeout(const Duration(seconds: 2));
    expect(s2Messages.first['type'], equals('auth_ok'));

    // broadcastして受信を確認
    server.broadcast({'type': 'clipboard', 'content_type': 'text', 'content': 'hello'});
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 50));
      return s2Messages.length < 2;
    }).timeout(const Duration(seconds: 2));

    final clip = s2Messages[1];
    expect(clip['type'], equals('clipboard'));
    expect(clip['content'], equals('hello'));

    await s1.close();
    await s2.close();
  });

  test('切断するとdevicesリストから削除される', () async {
    expect(server.devices.length, equals(0));

    final socket = await connectAndAuth();
    await socket.first; // auth_ok

    await Future.delayed(const Duration(milliseconds: 100));
    expect(server.devices.length, equals(1));

    await socket.close();
    await Future.delayed(const Duration(milliseconds: 100));
    expect(server.devices.length, equals(0));
  });
}
