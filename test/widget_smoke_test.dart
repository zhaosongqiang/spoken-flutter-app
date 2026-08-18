import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ielts_speaking/core/providers.dart';
import 'package:ielts_speaking/core/spoken_api.dart';
import 'package:ielts_speaking/features/practice_page.dart';
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

  testWidgets(
      'practice deep link initializes its session after the first frame',
      (tester) async {
    final pendingApi = Completer<SpokenApi>();
    final container = ProviderContainer(
      overrides: [
        spokenApiProvider.overrideWith((ref) => pendingApi.future),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(),
          home: const PracticePage(
            testId: 60,
            mode: 'seasonal',
            part: 1,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(container.read(practiceSessionProvider).testId, 60);
    expect(find.textContaining('正在加载'), findsNothing);
    expect(find.byType(ContentPlaceholder), findsOneWidget);
  });
}
