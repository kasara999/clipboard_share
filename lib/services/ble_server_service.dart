import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

import '../constants/ble_protocol.dart';
import 'ble_message_codec.dart';
import 'token_service.dart';

class BleConnectedDevice {
  final String id;
  final Central central;
  final DateTime connectedAt;
  final String platform;

  BleConnectedDevice({
    required this.id,
    required this.central,
    required this.connectedAt,
    required this.platform,
  });

  String get address => central.uuid.toString();
}

/// PC 側 BLE Peripheral（GATT サーバー + アドバタイズ）。
class BleServerService {
  PeripheralManager? _manager;
  PeripheralManager get _mgr => _manager!;

  GATTCharacteristic? _messageCharacteristic;
  final Map<String, Central> _notifyCentrals = {};
  final Map<String, bool> _authenticated = {};
  final Map<String, BleConnectedDevice> _devices = {};
  final Map<String, Map<int, String>> _assemblyBuffers = {};

  bool _advertising = false;
  bool _started = false;

  final _devicesController = StreamController<List<BleConnectedDevice>>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _logController = StreamController<String>.broadcast();

  Stream<List<BleConnectedDevice>> get devicesStream => _devicesController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<String> get logStream => _logController.stream;

  List<BleConnectedDevice> get devices => List.unmodifiable(_devices.values);
  bool get isAdvertising => _advertising;
  BluetoothLowEnergyState get state =>
      _manager?.state ?? BluetoothLowEnergyState.unknown;

  StreamSubscription? _readSub;
  StreamSubscription? _writeSub;
  StreamSubscription? _notifySub;
  StreamSubscription? _stateSub;

  static bool get isSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isAndroid;

  Future<void> start() async {
    if (!isSupported || _started) return;
    _manager ??= PeripheralManager();
    final manager = _manager!;
    TokenService.ensureInitialized();

    await _ensureAuthorized();

    _stateSub ??= manager.stateChanged.listen((event) async {
      if (event.state == BluetoothLowEnergyState.unauthorized) {
        await _ensureAuthorized();
      }
    });

    _readSub ??= manager.characteristicReadRequested.listen(_onReadRequested);
    _writeSub ??= manager.characteristicWriteRequested.listen(_onWriteRequested);
    _notifySub ??= manager.characteristicNotifyStateChanged.listen(_onNotifyStateChanged);

    await manager.removeAllServices();

    final deviceInfoBytes = Uint8List.fromList(
      utf8.encode(jsonEncode({
        'token': TokenService.token,
        'platform': Platform.operatingSystem,
        'v': BleProtocol.protocolVersion,
      })),
    );

    _messageCharacteristic = GATTCharacteristic.mutable(
      uuid: BleProtocol.messageUuid,
      properties: [
        GATTCharacteristicProperty.read,
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.writeWithoutResponse,
        GATTCharacteristicProperty.notify,
      ],
      permissions: [
        GATTCharacteristicPermission.read,
        GATTCharacteristicPermission.write,
      ],
      descriptors: [],
    );

    final service = GATTService(
      uuid: BleProtocol.serviceUuid,
      isPrimary: true,
      includedServices: [],
      characteristics: [
        GATTCharacteristic.immutable(
          uuid: BleProtocol.deviceInfoUuid,
          value: deviceInfoBytes,
          descriptors: [],
        ),
        _messageCharacteristic!,
      ],
    );

    await manager.addService(service);

    final advertisement = Advertisement(
      name: Platform.isWindows ? null : BleProtocol.advertiseName,
      serviceUUIDs: [BleProtocol.serviceUuid],
    );
    await manager.startAdvertising(advertisement);
    _advertising = true;
    _started = true;
    _log('Bluetooth 待ち受け開始 (${BleProtocol.advertiseName})');
  }

  Future<void> stop() async {
    if (!_started) return;
    final manager = _manager;
    if (manager == null) return;
    if (_advertising) {
      await manager.stopAdvertising();
      _advertising = false;
    }
    await manager.removeAllServices();
    _notifyCentrals.clear();
    _authenticated.clear();
    _devices.clear();
    _devicesController.add(devices);
    _started = false;
    _log('Bluetooth 待ち受け停止');
  }

  void broadcast(Map<String, dynamic> message, {String? excludeId}) {
    final characteristic = _messageCharacteristic;
    if (characteristic == null || !_advertising) return;

    final chunks = BleMessageCodec.encode(jsonEncode(message));
    for (final entry in _notifyCentrals.entries) {
      if (excludeId != null && entry.key == excludeId) continue;
      if (_authenticated[entry.key] != true) continue;
      unawaited(_notifyChunks(entry.value, characteristic, chunks));
    }
  }

  Future<void> _notifyChunks(
    Central central,
    GATTCharacteristic characteristic,
    List<Uint8List> chunks,
  ) async {
    for (final chunk in chunks) {
      try {
        await _mgr.notifyCharacteristic(
          central,
          characteristic,
          value: chunk,
        );
      } catch (_) {}
    }
  }

  Future<void> _ensureAuthorized() async {
    final manager = _manager;
    if (manager == null) return;
    if (manager.state == BluetoothLowEnergyState.unauthorized) {
      await manager.authorize();
    }
  }

  Future<void> _onReadRequested(GATTCharacteristicReadRequestedEventArgs event) async {
    final request = event.request;
    final characteristic = event.characteristic;
    if (characteristic.uuid != BleProtocol.deviceInfoUuid) {
      await _mgr.respondReadRequestWithError(
        request,
        error: GATTError.readNotPermitted,
      );
      return;
    }
    final deviceInfo = utf8.encode(jsonEncode({
      'token': TokenService.token,
      'platform': Platform.operatingSystem,
      'v': BleProtocol.protocolVersion,
    }));
    final offset = request.offset;
    final value = Uint8List.fromList(deviceInfo.sublist(offset.clamp(0, deviceInfo.length)));
    await _mgr.respondReadRequestWithValue(request, value: value);
  }

  Future<void> _onWriteRequested(GATTCharacteristicWriteRequestedEventArgs event) async {
    final request = event.request;
    final central = event.central;
    final centralId = central.uuid.toString();

    if (event.characteristic.uuid != BleProtocol.messageUuid) {
      await _mgr.respondWriteRequest(request);
      return;
    }

    await _mgr.respondWriteRequest(request);
    await _handleIncoming(central, request.value);
  }

  Future<void> _handleIncoming(Central central, Uint8List data) async {
    final centralId = central.uuid.toString();
    final assembly = _assemblyBuffers.putIfAbsent(centralId, () => {});
    final jsonText = BleMessageCodec.decodeChunk(data, assembly: assembly);
    if (jsonText == null) return;

    try {
      final message = jsonDecode(jsonText) as Map<String, dynamic>;
      final type = message['type'] as String?;

      if (_authenticated[centralId] != true) {
        if (type == 'auth') {
          final token = message['token'] as String?;
          if (token != null && TokenService.validate(token)) {
            _authenticated[centralId] = true;
            final platform = message['platform'] as String? ?? 'unknown';
            final device = BleConnectedDevice(
              id: centralId,
              central: central,
              connectedAt: DateTime.now(),
              platform: platform,
            );
            _devices[centralId] = device;
            _devicesController.add(devices);
            await _sendToCentral(central, {
              'type': 'auth_ok',
              'platform': Platform.operatingSystem,
            });
            _log('Bluetooth 認証成功 ($platform)');
          } else {
            await _sendToCentral(central, {
              'type': 'auth_error',
              'message': 'Invalid token',
            });
            _log('Bluetooth 認証失敗');
          }
        }
        return;
      }

      _messageController.add(message);
    } catch (_) {}
  }

  Future<void> _sendToCentral(Central central, Map<String, dynamic> message) async {
    final characteristic = _messageCharacteristic;
    if (characteristic == null) return;
    final chunks = BleMessageCodec.encode(jsonEncode(message));
    await _notifyChunks(central, characteristic, chunks);
  }

  void _onNotifyStateChanged(GATTCharacteristicNotifyStateChangedEventArgs event) {
    final centralId = event.central.uuid.toString();
    if (event.characteristic.uuid != BleProtocol.messageUuid) return;

    if (event.state) {
      _notifyCentrals[centralId] = event.central;
      _log('Bluetooth 通知購読開始 ($centralId)');
    } else {
      _notifyCentrals.remove(centralId);
      _authenticated.remove(centralId);
      _devices.remove(centralId);
      _assemblyBuffers.remove(centralId);
      _devicesController.add(devices);
      _log('Bluetooth 切断 ($centralId)');
    }
  }

  void _log(String message) {
    if (!_logController.isClosed) {
      _logController.add(message);
    }
  }

  void dispose() {
    _readSub?.cancel();
    _writeSub?.cancel();
    _notifySub?.cancel();
    _stateSub?.cancel();
    stop();
    _devicesController.close();
    _messageController.close();
    _logController.close();
  }
}
