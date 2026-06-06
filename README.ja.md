[English version](README.md)

# ClipSync — Windows / iPhone クリップボード共有アプリ

WindowsとiPhoneの間でクリップボードの内容をリアルタイムに同期するアプリです。
テキスト・画像どちらも対応しています。

## 背景・動機

iPhoneでコピーしたURLや画像をWindowsで貼り付けたいとき、毎回LINEのKeep Memoを経由しなければならないのが面倒で、クリップボードを直接共有できるアプリを開発しました。

## 機能

- WindowsでコピーしたテキストをiPhoneで貼り付けられる（逆も可）
- 画像のクリップボード共有にも対応
- クリップボード履歴を50件まで表示
- QRコードでiPhoneと簡単にペアリング
- トークン認証で同じWi-Fi内の不正接続を防止

## 動作環境

- **Windows**: Windows 10以降
- **iPhone**: iOS 16以降（別リポジトリ: [clipboard_share_ios](https://github.com/kasara999/clipboard_share_ios)）
- **ネットワーク**: WindowsとiPhoneが同じWi-Fiに接続していること

## インストール

**Windows:** [最新リリース](https://github.com/kasara999/clipboard_share/releases/latest)から `ClipSync-Setup.exe` をダウンロードして実行するだけでインストールできます。

**iPhone:** [TestFlight](https://testflight.apple.com/join/1mxzWq51) からiOSアプリをインストールしてください。

## 使い方

1. WindowsでClipSyncを起動する
2. 画面上部の「QR表示」ボタンをクリック
3. iPhoneのClipSyncアプリでQRコードを読み取る
4. 接続完了後、どちらでコピーしてももう一方に自動で同期される

## ファイル構成

```
lib/
├── main.dart                    # アプリの入口
├── screens/
│   └── home_screen.dart         # メイン画面・UI管理
└── services/
    ├── websocket_server.dart    # iPhoneとのWebSocket通信サーバー
    ├── clipboard_service.dart   # クリップボードの監視と書き込み
    └── token_service.dart       # 認証トークンの生成・検証
```

## 技術仕様

- **通信**: WebSocket（ポート8765）
- **認証**: 起動時に生成される32文字のランダムトークン
- **データ形式**: JSON（画像はBase64エンコード）
- **クリップボード検知**: 500msポーリング
