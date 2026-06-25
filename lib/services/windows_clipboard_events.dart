import 'package:flutter/services.dart';

/// Windows ネイティブの WM_CLIPBOARDUPDATE を EventChannel で受け取る。
class WindowsClipboardEvents {
  static const _channel = EventChannel('clipsync/clipboard_events');

  static Stream<void> get changes =>
      _channel.receiveBroadcastStream().map((_) {});
}
