import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';   // Flutterのクリップボード操作
import 'package:pasteboard/pasteboard.dart'; // 画像クリップボードの読み書き（プラグイン）

// クリップボードのデータ種別（テキストか画像か）
enum ClipboardItemType { text, image }

// 【ClipboardItem】
// クリップボード1件分のデータを表すクラス
// テキストと画像を同じ型で扱えるように統一している
class ClipboardItem {
  final ClipboardItemType type;
  final String? text;          // テキストの場合の内容
  final Uint8List? imageBytes; // 画像の場合のバイト列（生のピクセルデータ）
  final DateTime timestamp;    // いつクリップボードに入ったか

  // 名前付きコンストラクタ: ClipboardItem.text("hello") のように使う
  ClipboardItem.text(this.text)
      : type = ClipboardItemType.text,
        imageBytes = null,
        timestamp = DateTime.now();

  ClipboardItem.image(this.imageBytes)
      : type = ClipboardItemType.image,
        text = null,
        timestamp = DateTime.now();
}

// 【ClipboardService】
// クリップボードの変化を定期的に監視して、変化があればStreamに流す。
// また、iPhoneから受け取った内容をWindowsのクリップボードに書き込む。
//
// ファイル間の関係:
//   HomeScreen → startPolling()を呼んで監視開始、itemStreamを購読して変化を受け取る
//   HomeScreen → setFromRemote()を呼んでiPhoneのデータをクリップボードに書き込む
//   WebSocketServer → iPhoneからのメッセージをHomeScreen経由でここに渡す
class ClipboardService {
  // ポーリング間隔: 500ms（0.5秒）ごとにクリップボードをチェックする
  static const Duration _pollInterval = Duration(milliseconds: 500);

  Timer? _timer;           // 定期実行タイマー
  String? _lastText;       // 前回のテキスト（変化検知のために記憶しておく）
  String? _lastImageHash;  // 前回の画像の識別子（全データを比較するのは重いので先頭64バイトのハッシュを使う）

  // StreamController: データを川のように流す仕組み
  // broadcastにより複数の場所から同時に購読できる
  final _itemController = StreamController<ClipboardItem>.broadcast();
  Stream<ClipboardItem> get itemStream => _itemController.stream;

  // 自分でクリップボードに書き込んだ直後は、それをiPhoneに送り返さないためのフラグ
  bool _ignoreNext = false;

  // クリップボードの定期監視を開始する
  void startPolling() {
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  // クリップボードの定期監視を停止する
  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  // 実際に呼ばれるポーリング処理
  Future<void> _poll() async {
    // iPhoneから書き込んだ直後は1回だけスキップ（無限ループ防止）
    if (_ignoreNext) {
      _ignoreNext = false;
      return;
    }

    // テキストのチェック
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    // 前回と異なる内容があればStreamに流す
    if (text != null && text.isNotEmpty && text != _lastText) {
      _lastText = text;
      _itemController.add(ClipboardItem.text(text));
      return; // テキストがあれば画像チェックはスキップ
    }

    // 画像のチェック（pasteboard プラグインを使用）
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null) {
        // 画像全体を毎回比較するのは重いので、先頭64バイトをBase64にして比較
        final hash = base64Encode(imageBytes.sublist(0, imageBytes.length.clamp(0, 64)));
        if (hash != _lastImageHash) {
          _lastImageHash = hash;
          _itemController.add(ClipboardItem.image(imageBytes));
        }
      }
    } catch (_) {
      // このプラットフォームで画像クリップボードが使えない場合は無視
    }
  }

  // iPhoneから受け取った内容をWindowsのクリップボードに書き込む
  Future<void> setFromRemote(Map<String, dynamic> message) async {
    // 書き込んだ直後のポーリングでiPhoneに送り返さないようにフラグを立てる
    _ignoreNext = true;
    final type = message['content_type'] as String?;
    if (type == 'text') {
      final text = message['content'] as String?;
      if (text != null) {
        await Clipboard.setData(ClipboardData(text: text));
        _lastText = text; // ポーリングで再検知されないように記憶しておく
      }
    } else if (type == 'image') {
      // ネットワーク転送はBase64（バイナリをテキスト化）で行い、受信後に元のバイト列に戻す
      final base64 = message['content'] as String?;
      if (base64 != null) {
        final bytes = base64Decode(base64);
        await Pasteboard.writeImage(bytes);
        _lastImageHash = base64.substring(0, base64.length.clamp(0, 64));
      }
    }
  }

  // リソースを解放する（アプリ終了時に呼ばれる）
  void dispose() {
    stopPolling();
    _itemController.close();
  }
}
