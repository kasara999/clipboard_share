import 'package:clipboard_share/services/local_ip_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalIpService.isPrivateLanIPv4', () {
    test('accepts RFC1918 addresses', () {
      expect(LocalIpService.isPrivateLanIPv4('192.168.1.10'), isTrue);
      expect(LocalIpService.isPrivateLanIPv4('192.168.151.34'), isTrue);
      expect(LocalIpService.isPrivateLanIPv4('10.0.0.5'), isTrue);
      expect(LocalIpService.isPrivateLanIPv4('172.16.0.1'), isTrue);
    });

    test('rejects public and invalid addresses', () {
      expect(LocalIpService.isPrivateLanIPv4('8.8.8.8'), isFalse);
      expect(LocalIpService.isPrivateLanIPv4('0.0.0.0'), isFalse);
      expect(LocalIpService.isPrivateLanIPv4('127.0.0.1'), isFalse);
      expect(LocalIpService.isPrivateLanIPv4('not-an-ip'), isFalse);
    });
  });

  group('LocalIpService.isVirtualInterfaceName', () {
    test('detects common virtual adapters', () {
      expect(LocalIpService.isVirtualInterfaceName('vEthernet (Default Switch)'), isTrue);
      expect(LocalIpService.isVirtualInterfaceName('VMware Network Adapter VMnet8'), isTrue);
      expect(LocalIpService.isVirtualInterfaceName('Docker NAT'), isTrue);
    });

    test('keeps physical adapters', () {
      expect(LocalIpService.isVirtualInterfaceName('Ethernet'), isFalse);
      expect(LocalIpService.isVirtualInterfaceName('Wi-Fi'), isFalse);
      expect(LocalIpService.isVirtualInterfaceName('en0'), isFalse);
    });
  });

  group('LocalIpService.pickBestLanIp', () {
    test('prefers Ethernet over other interfaces', () {
      final entry = LocalIpService.pickBestLanIp([
        const LanIpEntry(interfaceName: 'vEthernet X', ip: '10.0.0.5'),
        const LanIpEntry(interfaceName: 'Ethernet', ip: '192.168.151.34'),
        const LanIpEntry(interfaceName: 'Wi-Fi', ip: '192.168.1.42'),
      ]);
      expect(entry?.ip, '192.168.151.34');
    });

    test('prefers 192.168.x when interface type is equal', () {
      final entry = LocalIpService.pickBestLanIp([
        const LanIpEntry(interfaceName: 'Ethernet', ip: '10.0.0.5'),
        const LanIpEntry(interfaceName: 'Ethernet 2', ip: '192.168.1.42'),
      ]);
      expect(entry?.ip, '192.168.1.42');
    });
  });
}
