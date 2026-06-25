import 'package:clipboard_share/services/local_ip_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalIpService.isPrivateLanIPv4', () {
    test('accepts RFC1918 addresses', () {
      expect(LocalIpService.isPrivateLanIPv4('192.168.1.10'), isTrue);
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
}
