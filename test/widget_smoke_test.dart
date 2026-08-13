import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_speaking/ui/design.dart';
import 'package:ielts_speaking/ui/widgets.dart';

void main() {
  testWidgets('state panel presents an actionable failure state',
      (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: AppFrame(
          body: StatePanel(
            title: '题库暂时无法加载',
            description: '网络连接不可用',
            action: '重新加载',
            onAction: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.text('题库暂时无法加载'), findsOneWidget);
    await tester.tap(find.text('重新加载'));
    expect(retried, isTrue);
  });
}
