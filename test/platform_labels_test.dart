import 'package:clipboard_share/constants/platform_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlatformLabels', () {
    test('mobile labels', () {
      expect(PlatformLabels.mobile('ios'), 'iPhone');
      expect(PlatformLabels.mobile('android'), 'Android');
      expect(PlatformLabels.mobile(null), 'Mobile');
    });
  });
}
