import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/clipboard_service.dart';
import '../services/token_service.dart';
import '../services/websocket_server.dart';

enum _Source { local, remote }

class _HistoryEntry {
  final ClipboardItem item;
  final _Source source;
  _HistoryEntry(this.item, this.source);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _server = WebSocketServer();
  final _clipboardService = ClipboardService();

  List<ConnectedDevice> _devices = [];
  final List<_HistoryEntry> _history = [];
  String? _localIp;
  bool _serverRunning = false;
  String? _serverError;

  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _startServer();
    _setupClipboardSync();
  }

  Future<void> _startServer() async {
    try {
      await _server.start();
      final ip = await NetworkInfo().getWifiIP();
      if (!mounted) return;
      setState(() {
        _serverRunning = true;
        _localIp = ip;
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
      await _clipboardService.setFromRemote(message);
      _addRemoteToHistory(message);
    }));
  }

  void _setupClipboardSync() {
    _clipboardService.startPolling();
    _subs.add(_clipboardService.itemStream.listen((item) {
      _addEntry(_HistoryEntry(item, _Source.local));
      _broadcastClipboard(item);
    }));
  }

  void _broadcastClipboard(ClipboardItem item) {
    if (item.type == ClipboardItemType.text && item.text != null) {
      _server.broadcast({'type': 'clipboard', 'content_type': 'text', 'content': item.text});
    } else if (item.type == ClipboardItemType.image && item.imageBytes != null) {
      _server.broadcast({
        'type': 'clipboard',
        'content_type': 'image',
        'content': base64Encode(item.imageBytes!),
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
    if (item != null) _addEntry(_HistoryEntry(item, _Source.remote));
  }

  void _addEntry(_HistoryEntry entry) {
    setState(() {
      _history.insert(0, entry);
      if (_history.length > 50) _history.removeLast();
    });
  }

  Future<void> _copyItemToClipboard(ClipboardItem item) async {
    if (item.type == ClipboardItemType.text && item.text != null) {
      await Clipboard.setData(ClipboardData(text: item.text!));
    } else if (item.type == ClipboardItemType.image && item.imageBytes != null) {
      // Pasteboard is a platform plugin — call via clipboard_service
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
        title: const Text('iPhoneで読み取ってください'),
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

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _server.dispose();
    _clipboardService.dispose();
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
          IconButton(
            icon: const Icon(Icons.qr_code),
            tooltip: 'QRコードを表示',
            onPressed: _serverRunning ? _showQrDialog : null,
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
      child: ListTile(
        leading: Icon(
          _serverRunning ? Icons.wifi : Icons.hourglass_empty,
          color: _serverRunning ? Colors.green : Colors.orange,
        ),
        title: Text(_serverRunning ? 'サーバー起動中' : '起動中...'),
        subtitle: _serverRunning
            ? Text('${_localIp ?? '-'}:${WebSocketServer.defaultPort}')
            : null,
        trailing: FilledButton.icon(
          icon: const Icon(Icons.qr_code, size: 18),
          label: const Text('QR表示'),
          onPressed: _serverRunning ? _showQrDialog : null,
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
                  Icon(Icons.phone_iphone, size: 16, color: Colors.grey),
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
                      const Icon(Icons.phone_iphone, size: 16, color: Colors.green),
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
                      leading: const Icon(Icons.phone_iphone, size: 18, color: Colors.blue),
                      title: Text(d.address, style: const TextStyle(fontSize: 13)),
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
        isRemote ? 'iPhone' : 'Local',
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
