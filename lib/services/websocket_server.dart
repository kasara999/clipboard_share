import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'token_service.dart';

// 【ConnectedDevice】
// 現在接続中のiPhone1台分の情報をまとめたデータクラス
class ConnectedDevice {
  final String id;           // デバイスを識別するためのユニークなID
  final WebSocket socket;    // このデバイスとの通信路（双方向のパイプ）
  final String address;      // iPhoneのIPアドレス（例: 192.168.1.5）
  final DateTime connectedAt; // 接続した日時

  ConnectedDevice({
    required this.id,
    required this.socket,
    required this.address,
    required this.connectedAt,
  });
}

// 【WebSocketServer】
// このアプリの中核。WindowsPC上でサーバーとして動き、
// iPhoneからの接続を待ち受けて、クリップボードの内容を双方向でやり取りする。
//
// ファイル間の関係:
//   TokenService → トークンの検証に使う
//   ClipboardService → このサーバーが受け取ったメッセージをClipboardServiceに渡す
//   HomeScreen → devicesStream/messageStreamを購読して画面を更新する
class WebSocketServer {
  // ポート番号: iPhoneがどの「窓口」に接続するかを示す番号
  // 8765は任意の値（使われていないポートなら何でもよい）
  static const int defaultPort = 8765;

  final int port;
  WebSocketServer({this.port = defaultPort});

  HttpServer? _server; // HTTPサーバー本体（WebSocketはHTTPのアップグレードで始まる）

  // 接続中のデバイスをMap（辞書）で管理: { デバイスID → ConnectedDevice }
  final Map<String, ConnectedDevice> _devices = {};

  // StreamController: データの「流れ」を作る仕組み
  // broadcastはStream（川）に複数のリスナーが同時に聞けるタイプ
  final _devicesController = StreamController<List<ConnectedDevice>>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  // 外部から購読できるStream（川）を公開する
  Stream<List<ConnectedDevice>> get devicesStream => _devicesController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  // 変更不可のリストとして現在のデバイス一覧を返す
  List<ConnectedDevice> get devices => List.unmodifiable(_devices.values);

  // サーバーを起動してiPhoneからの接続を待つ
  Future<void> start() async {
    // anyIPv4: このPCのすべてのネットワークインターフェースで待ち受ける
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    // 接続が来るたびに_handleRequestを呼ぶ
    _server!.listen(_handleRequest);
  }

  // サーバーを停止して全接続を切断する
  Future<void> stop() async {
    for (final device in _devices.values) {
      await device.socket.close();
    }
    _devices.clear();
    await _server?.close(force: true);
    _server = null;
  }

  // iPhoneから接続リクエストが来たときの処理
  void _handleRequest(HttpRequest request) async {
    // WebSocket接続でなければ拒否する（通常のHTTPリクエストは受け付けない）
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..close();
      return;
    }

    // HTTPをWebSocketにアップグレード（双方向通信の確立）
    final socket = await WebSocketTransformer.upgrade(request);
    final address = request.connectionInfo?.remoteAddress.address ?? 'unknown';

    // 認証状態の管理（最初はfalse、トークン確認後にtrueになる）
    bool authenticated = false;
    String? deviceId;

    // socketからデータが届くたびに呼ばれる
    socket.listen(
      (data) {
        try {
          // JSON文字列をDartのMapに変換（デシリアライズ）
          final message = jsonDecode(data as String) as Map<String, dynamic>;
          final type = message['type'] as String?;

          // 認証前は必ずトークン確認から始める（セキュリティゲート）
          if (!authenticated) {
            if (type == 'auth') {
              final token = message['token'] as String?;
              if (token != null && TokenService.validate(token)) {
                // トークンが正しければ認証成功
                authenticated = true;
                // ミリ秒タイムスタンプをIDとして使う（簡易的なユニークID）
                deviceId = DateTime.now().millisecondsSinceEpoch.toString();
                final device = ConnectedDevice(
                  id: deviceId!,
                  socket: socket,
                  address: address,
                  connectedAt: DateTime.now(),
                );
                _devices[deviceId!] = device;
                // デバイスリストが変わったことをHomeScreenに通知
                _devicesController.add(devices);
                // 認証OKをiPhoneに送信
                socket.add(jsonEncode({'type': 'auth_ok'}));
              } else {
                // トークンが違えば接続を拒否して切断
                socket.add(jsonEncode({'type': 'auth_error', 'message': 'Invalid token'}));
                socket.close();
              }
            }
            return; // 認証前はclipboardメッセージを処理しない
          }

          // 認証済みのメッセージはHomeScreenに流す
          _messageController.add(message);
        } catch (_) {
          // JSONが壊れていたりパースできない場合は無視する
        }
      },
      // 接続が切れたとき（iPhoneがアプリを閉じたなど）
      onDone: () {
        if (deviceId != null) {
          _devices.remove(deviceId);
          _devicesController.add(devices); // 画面のデバイスリストを更新
        }
      },
      // 通信エラーが起きたとき
      onError: (_) {
        if (deviceId != null) {
          _devices.remove(deviceId);
          _devicesController.add(devices);
        }
      },
    );
  }

  // 接続中の全iPhoneにメッセージを一斉送信する
  // excludeId: 送信元のデバイスには送り返さない場合に使う
  void broadcast(Map<String, dynamic> message, {String? excludeId}) {
    // DartのMapをJSON文字列に変換（シリアライズ）
    final data = jsonEncode(message);
    for (final device in _devices.values) {
      if (device.id != excludeId) {
        try {
          device.socket.add(data);
        } catch (_) {
          // 送信失敗は無視（次のポーリングで検知される）
        }
      }
    }
  }

  // リソースを解放する（アプリ終了時に呼ばれる）
  void dispose() {
    stop();
    _devicesController.close();
    _messageController.close();
  }
}
