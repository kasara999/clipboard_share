import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// LAN 上の IPv4 アドレス情報。
class LanIpEntry {
  final String interfaceName;
  final String ip;
  const LanIpEntry({required this.interfaceName, required this.ip});
}

/// 同一LAN内でモバイル端末から接続できるIPv4アドレスを返す。
/// Windows では network_info_plus の Wi-Fi IP が古い/仮想 NIC の値になりやすいため、
/// 実際の NIC 一覧を優先する。
class LocalIpService {
  static Future<String?> getLanIPv4() async {
    final entries = await getLanIpEntries();
    if (entries.isNotEmpty) {
      return pickBestLanIp(entries)?.ip;
    }

    // フォールバック（モバイル等）
    final wifiIp = await NetworkInfo().getWifiIP();
    if (wifiIp != null && _isPrivateIPv4(wifiIp)) {
      return wifiIp;
    }
    return null;
  }

  /// 接続候補となる LAN IP をすべて返す（診断・手動選択用）。
  static Future<List<LanIpEntry>> getLanIpEntries() async {
    final entries = <LanIpEntry>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        if (isVirtualInterfaceName(iface.name)) continue;
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (_isPrivateIPv4(ip)) {
            entries.add(LanIpEntry(interfaceName: iface.name, ip: ip));
          }
        }
      }
    } catch (_) {}

    if (entries.isNotEmpty || !Platform.isWindows) {
      return entries;
    }

    // Windows のみ: NIC 一覧が空のときだけ Wi-Fi API を使う
    final wifiIp = await NetworkInfo().getWifiIP();
    if (wifiIp != null && _isPrivateIPv4(wifiIp)) {
      entries.add(LanIpEntry(interfaceName: 'Wi-Fi', ip: wifiIp));
    }
    return entries;
  }

  /// 仮想NIC（vEthernet, VMware, Docker 等）かどうか。
  static bool isVirtualInterfaceName(String name) {
    final lower = name.toLowerCase();
    const virtualHints = [
      'vethernet',
      'vmware',
      'virtualbox',
      'vbox',
      'hyper-v',
      'docker',
      'wsl',
      'loopback',
      'teredo',
      'bluetooth',
      'npcap',
      'hamachi',
      'zerotier',
      'tailscale',
      'tap-windows',
    ];
    return virtualHints.any(lower.contains);
  }

  /// 候補の中からモバイル端末が到達しやすい IP を選ぶ。
  static LanIpEntry? pickBestLanIp(Iterable<LanIpEntry> candidates) {
    final list = candidates.toList();
    if (list.isEmpty) return null;
    list.sort((a, b) {
      final byIface = _interfacePriority(a.interfaceName)
          .compareTo(_interfacePriority(b.interfaceName));
      if (byIface != 0) return byIface;
      final byPrefix = _ipPrefixPriority(a.ip).compareTo(_ipPrefixPriority(b.ip));
      if (byPrefix != 0) return byPrefix;
      return a.ip.compareTo(b.ip);
    });
    return list.first;
  }

  static int _interfacePriority(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('ethernet') || lower.contains('イーサネット')) return 0;
    if (lower.contains('wi-fi') ||
        lower.contains('wifi') ||
        lower.contains('wlan') ||
        lower.contains('ワイヤレス')) {
      return 1;
    }
    return 2;
  }

  static int _ipPrefixPriority(String ip) {
    if (ip.startsWith('192.168.')) return 0;
    if (ip.startsWith('10.')) return 1;
    if (ip.startsWith('172.')) return 2;
    return 3;
  }

  static bool _isPrivateIPv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return false;
    final a = nums[0]!;
    final b = nums[1]!;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  static bool isPrivateLanIPv4(String ip) => _isPrivateIPv4(ip);
}
