import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import 'windows_clipboard_events.dart';

enum ClipboardItemType { text, image }

class ClipboardItem {
  final ClipboardItemType type;
  final String? text;
  final Uint8List? imageBytes;
  final DateTime timestamp;

  ClipboardItem.text(this.text)
      : type = ClipboardItemType.text,
        imageBytes = null,
        timestamp = DateTime.now();

  ClipboardItem.image(this.imageBytes)
      : type = ClipboardItemType.image,
        text = null,
        timestamp = DateTime.now();
}

/// クリップボードの変化を監視して Stream に流す。
/// Windows: WM_CLIPBOARDUPDATE（イベント駆動）
/// その他: 500ms ポーリング（macOS 等）
class ClipboardService {
  static const Duration _pollInterval = Duration(milliseconds: 500);

  Timer? _timer;
  StreamSubscription<void>? _clipboardSub;
  String? _lastText;
  String? _lastImageHash;
  bool _ignoreNext = false;

  final _itemController = StreamController<ClipboardItem>.broadcast();
  Stream<ClipboardItem> get itemStream => _itemController.stream;

  void startPolling() {
    if (_timer != null || _clipboardSub != null) return;

    if (Platform.isWindows) {
      _clipboardSub = WindowsClipboardEvents.changes.listen(
        (_) => unawaited(_readClipboard()),
      );
      return;
    }

    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_readClipboard()));
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    unawaited(_clipboardSub?.cancel());
    _clipboardSub = null;
  }

  Future<void> _readClipboard() async {
    if (_ignoreNext) {
      _ignoreNext = false;
      return;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty && text != _lastText) {
      _lastText = text;
      _itemController.add(ClipboardItem.text(text));
      return;
    }

    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null) {
        final hash = base64Encode(imageBytes.sublist(0, imageBytes.length.clamp(0, 64)));
        if (hash != _lastImageHash) {
          _lastImageHash = hash;
          _itemController.add(ClipboardItem.image(imageBytes));
        }
      }
    } catch (_) {}
  }

  /// リモート受信直後に OS クリップボード連携（Universal Clipboard 等）で
  /// 同じ内容がローカルとして検知されるのを防ぐ。
  void noteRemoteContent(ClipboardItem item) {
    if (item.type == ClipboardItemType.text) {
      _lastText = item.text;
    } else if (item.imageBytes != null) {
      _lastImageHash =
          base64Encode(item.imageBytes!.sublist(0, item.imageBytes!.length.clamp(0, 64)));
    }
  }

  Future<void> setFromRemote(Map<String, dynamic> message) async {
    _ignoreNext = true;
    final type = message['content_type'] as String?;
    if (type == 'text') {
      final text = message['content'] as String?;
      if (text != null) {
        await Clipboard.setData(ClipboardData(text: text));
        _lastText = text;
      }
    } else if (type == 'image') {
      final base64 = message['content'] as String?;
      if (base64 != null) {
        final bytes = base64Decode(base64);
        await Pasteboard.writeImage(bytes);
        _lastImageHash = base64.substring(0, base64.length.clamp(0, 64));
      }
    }
  }

  void dispose() {
    stopPolling();
    _itemController.close();
  }
}
