import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// 同一LAN内でiPhoneから接続できるIPv4アドレスを返す。
/// Wi-Fi未接続でも有線LAN（Ethernet）のIPを拾う。
class LocalIpService {
  static Future<String?> getLanIPv4() async {
    final wifiIp = await NetworkInfo().getWifiIP();
    if (wifiIp != null && _isPrivateIPv4(wifiIp)) {
      return wifiIp;
    }

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (_isPrivateIPv4(ip)) {
            return ip;
          }
        }
      }
    } catch (_) {}

    return wifiIp;
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
