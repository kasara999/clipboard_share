import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../constants/platform_labels.dart';
import '../services/clipboard_service.dart';
import '../services/local_ip_service.dart';
import '../services/token_service.dart';
import '../services/websocket_server.dart';
import '../services/windows_firewall_service.dart';

// 【home_screen.dart】
// アプリの画面全体を管理するファイル。
// WebSocketServerとClipboardServiceを組み合わせて、
// 「クリップボードの変化を検知 → iPhoneに送信」
// 「iPhoneからの受信 → クリップボードに書き込み」を実現している。

// クリップボードの内容がどちら側から来たかを区別するための列挙型
enum _Source { local, remote } // local=このPC, remote=モバイル

// 履歴1件分のデータ（内容 + 送信元）
class _HistoryEntry {
  final ClipboardItem item;
  final _Source source;
  final String? remoteLabel;
  _HistoryEntry(this.item, this.source, {this.remoteLabel});
}

// StatefulWidget: 状態（変化するデータ）を持つ画面
// 接続デバイス数やクリップボード履歴が変わるたびに画面を再描画する
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // サービスクラスのインスタンスを作成（画面とサービスを繋ぐ）
  final _server = WebSocketServer();
  final _clipboardService = ClipboardService();

  List<ConnectedDevice> _devices = [];       // 現在接続中のモバイル端末一覧
  final List<_HistoryEntry> _history = [];   // クリップボード履歴（最大50件）
  String? _localIp;
  List<LanIpEntry> _lanIpEntries = [];
  bool _serverRunning = false;
  String? _serverError;
  String? _firewallHint;
  int _inboundRequestCount = 0;
  final List<String> _connectionLogs = [];

  // StreamSubscription: Streamの購読を管理するオブジェクト
  // disposeで一括キャンセルできるようにリストで管理する
  final List<StreamSubscription> _subs = [];

  // initState: ウィジェットが画面に表示される直前に1回だけ呼ばれる
  @override
  void initState() {
    super.initState();
    _startServer();        // WebSocketサーバーを起動
    _setupClipboardSync(); // クリップボード監視を開始
  }

  // WebSocketサーバーを起動して、接続・メッセージの監視を開始する
  Future<void> _startServer() async {
    try {
      if (Platform.isWindows) {
        final fw = await WindowsFirewallService.tryAllowInboundPort(
          WebSocketServer.defaultPort,
        );
        if (!mounted) return;
        _firewallHint = switch (fw.status) {
          FirewallSetupStatus.added => 'Windows ファイアウォールにポート ${WebSocketServer.defaultPort} を許可しました',
          FirewallSetupStatus.alreadyExists => null,
          FirewallSetupStatus.skipped => null,
          FirewallSetupStatus.failed =>
            'ファイアウォール規則の自動追加に失敗しました。McAfee 等でポート ${WebSocketServer.defaultPort} を許可してください。',
        };
      }

      await _server.start();
      final entries = await LocalIpService.getLanIpEntries();
      final ip = LocalIpService.pickBestLanIp(entries)?.ip ??
          await LocalIpService.getLanIPv4();
      if (!mounted) return;
      setState(() {
        _serverRunning = true;
        _localIp = ip;
        _lanIpEntries = entries;
        _inboundRequestCount = _server.inboundRequestCount;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverError = e.toString());
      return;
    }

    _subs.add(_server.devicesStream.listen((devices) {
      setState(() => _devices = devices);
    }));

    _subs.add(_server.messageStream.listen((message) async {
      _addRemoteToHistory(message);
    }));

    _subs.add(_server.connectionLogStream.listen((event) {
      if (!mounted) return;
      setState(() {
        _inboundRequestCount = _server.inboundRequestCount;
        _connectionLogs.insert(0, event.message);
        if (_connectionLogs.length > 5) _connectionLogs.removeLast();
      });
    }));
  }

  Future<void> _refreshLocalIp() async {
    final entries = await LocalIpService.getLanIpEntries();
    final ip = LocalIpService.pickBestLanIp(entries)?.ip;
    if (!mounted) return;
    setState(() {
      _lanIpEntries = entries;
      _localIp = ip;
    });
  }

  // クリップボードの定期監視を開始して、変化があれば全iPhoneに送信する
  void _setupClipboardSync() {
    _clipboardService.startPolling();
    // itemStream: ClipboardServiceからクリップボード変化のイベントが流れてくるStream
    _subs.add(_clipboardService.itemStream.listen((item) {
      _onLocalClipboard(item);
    }));
  }

  String get _localPlatformLabel => PlatformLabels.desktopLocal();

  String _remoteDeviceLabel(Map<String, dynamic> message) {
    return PlatformLabels.mobile(message['origin'] as String?);
  }

  IconData _deviceIcon(String platform) {
    switch (platform) {
      case 'android':
        return Icons.android;
      case 'ios':
        return Icons.phone_iphone;
      default:
        return Icons.smartphone;
    }
  }

  bool _sameClipboardContent(ClipboardItem a, ClipboardItem b) {
    if (a.type != b.type) return false;
    if (a.type == ClipboardItemType.text) {
      return a.text == b.text;
    }
    final aBytes = a.imageBytes;
    final bBytes = b.imageBytes;
    if (aBytes == null || bBytes == null) return false;
    if (aBytes.length != bBytes.length) return false;
    final n = aBytes.length.clamp(0, 64);
    for (var i = 0; i < n; i++) {
      if (aBytes[i] != bBytes[i]) return false;
    }
    return true;
  }

  void _onLocalClipboard(ClipboardItem item) {
    if (_history.isNotEmpty &&
        _history.first.source == _Source.remote &&
        _sameClipboardContent(_history.first.item, item)) {
      return;
    }
    _addEntry(_HistoryEntry(item, _Source.local));
    _broadcastClipboard(item);
  }
  void _broadcastClipboard(ClipboardItem item) {
    if (item.type == ClipboardItemType.text && item.text != null) {
      _server.broadcast({
        'type': 'clipboard',
        'content_type': 'text',
        'content': item.text,
        'origin': Platform.operatingSystem,
      });
    } else if (item.type == ClipboardItemType.image && item.imageBytes != null) {
      _server.broadcast({
        'type': 'clipboard',
        'content_type': 'image',
        'content': base64Encode(item.imageBytes!),
        'origin': Platform.operatingSystem,
      });
    }
  }

  void _addRemoteToHistory(Map<String, dynamic> message) {
    final type = message['content_type'] as String?;
    ClipboardItem? item;
    if (type == 'text') {
      item = ClipboardItem.text(message['content'] as String?);
    } else if (type == 'image') {
      final bytes = base64Decode(message['content'] as String);
      item = ClipboardItem.image(bytes);
    }
    if (item == null) return;
    final remoteItem = item;
    final label = _remoteDeviceLabel(message);

    _clipboardService.noteRemoteContent(remoteItem);

    if (_history.isNotEmpty &&
        _history.first.source == _Source.local &&
        _sameClipboardContent(_history.first.item, remoteItem)) {
      setState(() => _history[0] = _HistoryEntry(remoteItem, _Source.remote, remoteLabel: label));
      return;
    }
    _addEntry(_HistoryEntry(remoteItem, _Source.remote, remoteLabel: label));
  }

  void _addEntry(_HistoryEntry entry) {
    setState(() {
      _history.insert(0, entry);
      if (_history.length > 50) _history.removeLast();
    });
  }

  Future<void> _copyItemToClipboard(ClipboardItem item) async {
    if (item.type == ClipboardItemType.text && item.text != null) {
      await _clipboardService.setFromRemote({
        'content_type': 'text',
        'content': item.text,
      });
    } else if (item.type == ClipboardItemType.image && item.imageBytes != null) {
      await _clipboardService.setFromRemote({
        'content_type': 'image',
        'content': base64Encode(item.imageBytes!),
      });
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('クリップボードにコピーしました'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _showQrDialog() {
    final ip = _localIp ?? '0.0.0.0';
    final token = TokenService.token;
    final qrData = 'clipsync://$ip:${WebSocketServer.defaultPort}?token=$token';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('スマホで読み取ってください'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            QrImageView(data: qrData, size: 240),
            const SizedBox(height: 12),
            Text(
              '$ip:${WebSocketServer.defaultPort}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            _TokenRow(token: token),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  // dispose: ウィジェットが画面から取り除かれるときに呼ばれる（後片付け）
  // メモリリークを防ぐために、Streamの購読やタイマーを必ず解放する
  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel(); // 全Streamの購読を停止
    }
    _server.dispose();         // WebSocketサーバーを停止
    _clipboardService.dispose(); // クリップボード監視を停止
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ClipSync'),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '履歴をクリア',
              onPressed: () => setState(() => _history.clear()),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusCard(),
          _buildDeviceSection(),
          const Divider(height: 1),
          Expanded(child: _buildHistory()),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    if (_serverError != null) {
      return Card(
        margin: const EdgeInsets.all(12),
        color: Colors.red[50],
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: const Text('起動エラー', style: TextStyle(color: Colors.red)),
          subtitle: Text(_serverError!, style: const TextStyle(fontSize: 12)),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _serverRunning ? Icons.wifi : Icons.hourglass_empty,
                  color: _serverRunning ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _serverRunning ? 'サーバー起動中' : '起動中...',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.qr_code, size: 18),
                  label: const Text('QR表示'),
                  onPressed: _serverRunning && _localIp != null ? _showQrDialog : null,
                ),
              ],
            ),
            if (_serverRunning) ...[
              const SizedBox(height: 8),
              Text(
                _localIp != null
                    ? '接続先: $_localIp:${WebSocketServer.defaultPort}'
                    : 'IPアドレスを取得できません（Wi-Fi/有線LANを確認）',
                style: TextStyle(
                  fontSize: 12,
                  color: _localIp != null ? null : Colors.orange[800],
                ),
              ),
              if (_lanIpEntries.length > 1) ...[
                const SizedBox(height: 4),
                Text(
                  '検出したIP: ${_lanIpEntries.map((e) => e.ip).join(', ')}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
                const SizedBox(height: 2),
                const Text(
                  'ipconfig の IPv4 と一致しない場合は QR を開く前に更新してください',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '受信ログ: $_inboundRequestCount 件'
                '${_inboundRequestCount == 0 ? '（スマホからまだ届いていません）' : ''}',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
              if (_connectionLogs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _connectionLogs.first,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              if (_firewallHint != null) ...[
                const SizedBox(height: 4),
                Text(_firewallHint!, style: TextStyle(fontSize: 11, color: Colors.blue[800])),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _refreshLocalIp,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('IPを再取得'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSection() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: _devices.isEmpty
          ? const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.smartphone, size: 16, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('接続中のデバイスなし', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Icon(Icons.smartphone, size: 16, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        '接続中 ${_devices.length}台',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                ..._devices.map((d) => ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      leading: Icon(_deviceIcon(d.platform), size: 18, color: Colors.blue),
                      title: Text(
                        '${PlatformLabels.mobile(d.platform)} · ${d.address}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '接続: ${_formatTime(d.connectedAt)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    )),
              ],
            ),
    );
  }

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.content_paste_off, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('クリップボード履歴なし', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            '履歴 (${_history.length}件)',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            itemCount: _history.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _buildHistoryItem(_history[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryItem(_HistoryEntry entry) {
    final item = entry.item;
    final isRemote = entry.source == _Source.remote;

    final sourceChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: isRemote ? Colors.blue[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isRemote ? (entry.remoteLabel ?? 'Mobile') : _localPlatformLabel,
        style: TextStyle(
          fontSize: 10,
          color: isRemote ? Colors.blue[700] : Colors.green[700],
        ),
      ),
    );

    if (item.type == ClipboardItemType.text) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.text_fields, size: 18),
        title: Text(item.text ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            sourceChip,
            const SizedBox(width: 6),
            Text(_formatTime(item.timestamp), style: const TextStyle(fontSize: 11)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 16),
          tooltip: 'コピー',
          onPressed: () => _copyItemToClipboard(item),
        ),
        onTap: () => _copyItemToClipboard(item),
      );
    } else {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.image, size: 18),
        title: item.imageBytes != null
            ? Image.memory(
                item.imageBytes!,
                height: 56,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
              )
            : const Text('画像'),
        subtitle: Row(
          children: [
            sourceChip,
            const SizedBox(width: 6),
            Text(_formatTime(item.timestamp), style: const TextStyle(fontSize: 11)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy, size: 16),
          tooltip: 'コピー',
          onPressed: () => _copyItemToClipboard(item),
        ),
        onTap: () => _copyItemToClipboard(item),
      );
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}

class _TokenRow extends StatefulWidget {
  final String token;
  const _TokenRow({required this.token});

  @override
  State<_TokenRow> createState() => _TokenRowState();
}

class _TokenRowState extends State<_TokenRow> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SelectableText(
            widget.token,
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey),
          ),
        ),
        IconButton(
          icon: Icon(_copied ? Icons.check : Icons.copy, size: 14),
          tooltip: 'トークンをコピー',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.token));
            setState(() => _copied = true);
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) setState(() => _copied = false);
          },
        ),
      ],
    );
  }
}
