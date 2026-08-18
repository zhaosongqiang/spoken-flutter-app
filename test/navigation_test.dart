import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ielts_speaking/core/models.dart';
import 'package:ielts_speaking/core/providers.dart';
import 'package:ielts_speaking/features/feedback_page.dart';
import 'package:ielts_speaking/router.dart';

void main() {
  testWidgets('page navigation notifies without treating dialogs as pages',
      (tester) async {
    var pageChanges = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [PageChangeObserver(() => pageChanges++)],
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      content: const Text('弹窗'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('打开弹窗'),
                ),
                TextButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        body: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('返回首页'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('打开页面'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开弹窗'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(pageChanges, 0);

    await tester.tap(find.text('打开页面'));
    await tester.pumpAndSettle();
    expect(pageChanges, 1);
    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(pageChanges, 2);
  });

  testWidgets('feedback back button pops to the existing source page',
      (tester) async {
    final pendingBootstrap = Completer<AccountBootstrap>();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('原页面')),
        ),
        GoRoute(
          path: '/feedback',
          builder: (context, state) => const FeedbackPage(
            recordId: 1,
            detailId: 2,
            source: 'history',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountBootstrapProvider.overrideWith(
            (ref) => pendingBootstrap.future,
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    router.push('/feedback');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('评测反馈'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('原页面'), findsOneWidget);
  });
}
