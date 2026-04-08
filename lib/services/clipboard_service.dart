import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

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

class ClipboardService {
  static const Duration _pollInterval = Duration(milliseconds: 500);

  Timer? _timer;
  String? _lastText;
  String? _lastImageHash;

  final _itemController = StreamController<ClipboardItem>.broadcast();
  Stream<ClipboardItem> get itemStream => _itemController.stream;

  // Set to true to prevent re-broadcasting items we just set ourselves
  bool _ignoreNext = false;

  void startPolling() {
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_ignoreNext) {
      _ignoreNext = false;
      return;
    }

    // Check text
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty && text != _lastText) {
      _lastText = text;
      _itemController.add(ClipboardItem.text(text));
      return;
    }

    // Check image
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null) {
        final hash = base64Encode(imageBytes.sublist(0, imageBytes.length.clamp(0, 64)));
        if (hash != _lastImageHash) {
          _lastImageHash = hash;
          _itemController.add(ClipboardItem.image(imageBytes));
        }
      }
    } catch (_) {
      // pasteboard image not available on this platform
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
