import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'token_service.dart';

class ConnectedDevice {
  final String id;
  final WebSocket socket;
  final String address;
  final DateTime connectedAt;

  ConnectedDevice({
    required this.id,
    required this.socket,
    required this.address,
    required this.connectedAt,
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

  Stream<List<ConnectedDevice>> get devicesStream => _devicesController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  List<ConnectedDevice> get devices => List.unmodifiable(_devices.values);

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    for (final device in _devices.values) {
      await device.socket.close();
    }
    _devices.clear();
    await _server?.close(force: true);
    _server = null;
  }

  void _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.badRequest
        ..close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    final address = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    bool authenticated = false;
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
                deviceId = DateTime.now().millisecondsSinceEpoch.toString();
                final device = ConnectedDevice(
                  id: deviceId!,
                  socket: socket,
                  address: address,
                  connectedAt: DateTime.now(),
                );
                _devices[deviceId!] = device;
                _devicesController.add(devices);
                socket.add(jsonEncode({'type': 'auth_ok'}));
              } else {
                socket.add(jsonEncode({'type': 'auth_error', 'message': 'Invalid token'}));
                socket.close();
              }
            }
            return;
          }

          _messageController.add(message);
        } catch (_) {
          // ignore malformed messages
        }
      },
      onDone: () {
        if (deviceId != null) {
          _devices.remove(deviceId);
          _devicesController.add(devices);
        }
      },
      onError: (_) {
        if (deviceId != null) {
          _devices.remove(deviceId);
          _devicesController.add(devices);
        }
      },
    );
  }

  void broadcast(Map<String, dynamic> message, {String? excludeId}) {
    final data = jsonEncode(message);
    for (final device in _devices.values) {
      if (device.id != excludeId) {
        try {
          device.socket.add(data);
        } catch (_) {
          // ignore send errors
        }
      }
    }
  }

  void dispose() {
    stop();
    _devicesController.close();
    _messageController.close();
  }
}
