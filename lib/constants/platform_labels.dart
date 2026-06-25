import 'dart:io' show Platform;

/// OS 名（dart:io Platform.operatingSystem）を UI 表示用ラベルに変換する。
class PlatformLabels {
  PlatformLabels._();

  static String desktopLocal() {
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Local';
  }

  static String mobile(String? platform) {
    switch (platform) {
      case 'ios':
        return 'iPhone';
      case 'android':
        return 'Android';
      default:
        return 'Mobile';
    }
  }
}
