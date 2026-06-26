import 'dart:io';

/// Windows 向け: ポート 8765 の受信をファイアウォールで許可する。
class WindowsFirewallService {
  static const ruleName = 'ClipSync';

  /// 受信規則を追加する。管理者権限がないと失敗する。
  static Future<FirewallSetupResult> tryAllowInboundPort(int port) async {
    if (!Platform.isWindows) {
      return const FirewallSetupResult(status: FirewallSetupStatus.skipped);
    }

    final result = await Process.run('netsh', [
      'advfirewall',
      'firewall',
      'add',
      'rule',
      'name=$ruleName',
      'dir=in',
      'action=allow',
      'protocol=TCP',
      'localport=$port',
      'profile=any',
      'enable=yes',
    ], runInShell: true);

    if (result.exitCode == 0) {
      return const FirewallSetupResult(status: FirewallSetupStatus.added);
    }

    final output = '${result.stdout}${result.stderr}';
    if (output.contains('already exists') || output.contains('既に存在')) {
      return const FirewallSetupResult(status: FirewallSetupStatus.alreadyExists);
    }

    return FirewallSetupResult(
      status: FirewallSetupStatus.failed,
      detail: _trimOutput(output),
    );
  }

  static String _trimOutput(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '管理者権限が必要な場合があります';
    return text.length > 200 ? '${text.substring(0, 200)}...' : text;
  }
}

enum FirewallSetupStatus { skipped, added, alreadyExists, failed }

class FirewallSetupResult {
  final FirewallSetupStatus status;
  final String? detail;
  const FirewallSetupResult({required this.status, this.detail});
}
