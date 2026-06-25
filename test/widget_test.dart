import 'package:clipboard_share/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ホーム画面が表示される', (WidgetTester tester) async {
    await tester.pumpWidget(const ClipSyncApp());
    await tester.pump();

    expect(find.text('ClipSync'), findsOneWidget);
  });
}
