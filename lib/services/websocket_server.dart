import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'token_service.dart';

/// サーバー側の接続診断イベント。
class ServerConnectionEvent {
  final DateTime at;
  final String message;
  const ServerConnectionEvent({required this.at, required this.message});
}

// 【ConnectedDevice】
// 現在接続中のモバイル端末1台分の情報をまとめたデータクラス
class ConnectedDevice {
  final String id;
  final WebSocket socket;
  final String address;
  final DateTime connectedAt;
  final String platform;

  ConnectedDevice({
    required this.id,
    required this.socket,
    required this.address,
    required this.connectedAt,
    required this.platform,
  });
}

class WebSocketServer {
  static const int defaultPort = 8765;

  final int port;
  WebSocketServer({this.port = defaultPort});

  HttpServer? _server;

  final Map<String, ConnectedDevice> _devices = {};

  final _devicesController = StreamController<List<ConnectedDevice>>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionLogController =
      StreamController<ServerConnectionEvent>.broadcast();

  Stream<List<ConnectedDevice>> get devicesStream => _devicesController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<ServerConnectionEvent> get connectionLogStream =>
      _connectionLogController.stream;

  List<ConnectedDevice> get devices => List.unmodifiable(_devices.values);

  int get inboundRequestCount => _inboundRequestCount;
  int _inboundRequestCount = 0;

  Future<void> start() async {
    TokenService.ensureInitialized();
    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );
    _log('ポート $port で待ち受け開始 (0.0.0.0:$port)');
    _server!.listen(
      _handleRequest,
      onError: (Object e) => _log('サーバーエラー: $e'),
    );
  }

  Future<void> stop() async {
    for (final device in _devices.values) {
      await device.socket.close();
    }
    _devices.clear();
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final remote = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    _inboundRequestCount++;
    _log('接続要求 #$inboundRequestCount from $remote');

    try {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        _log('$remote → WebSocket 以外の要求を拒否');
        request.response
          ..statusCode = HttpStatus.badRequest
          ..close();
        return;
      }

      final socket = await WebSocketTransformer.upgrade(request);
      final address = remote;
      _log('$remote → WebSocket 確立');

      var authenticated = false;
      String? deviceId;

      socket.listen(
        (data) {
          try {
            final message = jsonDecode(data as String) as Map<String, dynamic>;
            final type = message['type'] as String?;

            if (!authenticated) {
              if (type == 'auth') {
                final token = message['token'] as String?;
                if (token != null && TokenService.validate(token)) {
                  authenticated = true;
                  final clientPlatform =
                      message['platform'] as String? ?? 'unknown';
                  deviceId = DateTime.now().millisecondsSinceEpoch.toString();
                  final device = ConnectedDevice(
                    id: deviceId!,
                    socket: socket,
                    address: address,
                    connectedAt: DateTime.now(),
                    platform: clientPlatform,
                  );
                  _devices[deviceId!] = device;
                  _devicesController.add(devices);
                  socket.add(jsonEncode({
                    'type': 'auth_ok',
                    'platform': Platform.operatingSystem,
                  }));
                  _log('$remote → 認証成功 ($clientPlatform)');
                } else {
                  socket.add(jsonEncode({
                    'type': 'auth_error',
                    'message': 'Invalid token',
                  }));
                  _log('$remote → 認証失敗（トークン不一致）');
                  socket.close();
                }
              }
              return;
            }

            _messageController.add(message);
          } catch (_) {}
        },
        onDone: () {
          if (deviceId != null) {
            _devices.remove(deviceId);
            _devicesController.add(devices);
            _log('$remote → 切断');
          }
        },
        onError: (_) {
          if (deviceId != null) {
            _devices.remove(deviceId);
            _devicesController.add(devices);
            _log('$remote → エラーで切断');
          }
        },
      );
    } catch (e) {
      _log('$remote → 処理エラー: $e');
      try {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..close();
      } catch (_) {}
    }
  }

  void broadcast(Map<String, dynamic> message, {String? excludeId}) {
    final data = jsonEncode(message);
    for (final device in _devices.values) {
      if (device.id != excludeId) {
        try {
          device.socket.add(data);
        } catch (_) {}
      }
    }
  }

  void _log(String message) {
    if (!_connectionLogController.isClosed) {
      _connectionLogController.add(
        ServerConnectionEvent(at: DateTime.now(), message: message),
      );
    }
  }

  void dispose() {
    stop();
    _devicesController.close();
    _messageController.close();
    _connectionLogController.close();
  }
}
