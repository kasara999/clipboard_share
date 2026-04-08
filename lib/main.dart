import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

// 【main.dart】
// アプリの入口ファイル。Flutterはここから実行を開始する。
//
// ファイル全体の関係図:
//
//   main.dart
//   └── HomeScreen（画面・UIの管理）
//       ├── WebSocketServer（iPhoneとのWebSocket通信サーバー）
//       │   └── TokenService（接続認証用トークンの生成・検証）
//       └── ClipboardService（クリップボードの監視と書き込み）
//
// データの流れ:
//   [Windows クリップボード変化]
//     → ClipboardService がポーリングで検知
//     → HomeScreen が受け取り
//     → WebSocketServer が全iPhoneに送信
//
//   [iPhoneからのコピー]
//     → WebSocketServer が受信
//     → HomeScreen が受け取り
//     → ClipboardService がWindowsのクリップボードに書き込み

// runApp: Flutterアプリを起動する関数
void main() {
  runApp(const ClipSyncApp());
}

// StatelessWidget: 状態（変化するデータ）を持たない画面パーツ
// アプリ全体の設定（テーマ・タイトルなど）を定義する器
class ClipSyncApp extends StatelessWidget {
  const ClipSyncApp({super.key});

  // build: このウィジェットがどんな見た目かを返すメソッド
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClipSync',
      debugShowCheckedModeBanner: false, // 右上のデバッグバナーを非表示
      theme: ThemeData(
        // indigoを基調色として、Material3デザインのカラーパレットを自動生成
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(), // 最初に表示する画面
    );
  }
}
