import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'core/models.dart';
import 'features/feedback_page.dart';
import 'features/history_page.dart';
import 'features/practice_page.dart';
import 'features/record_detail_page.dart';
import 'features/topic_selection_page.dart';

GoRouter createAppRouter({required VoidCallback onPageChanged}) {
  // Imperative push routes must remain deep-linkable after a Web refresh.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  return GoRouter(
    observers: [PageChangeObserver(onPageChanged)],
    routes: [
      GoRoute(
          path: '/', builder: (context, state) => const TopicSelectionPage()),
      GoRoute(
        path: '/practice/:testId',
        builder: (context, state) {
          final test = state.extra is TestItem ? state.extra as TestItem : null;
          return PracticePage(
            testId: int.tryParse(state.pathParameters['testId'] ?? '') ?? 0,
            mode: state.uri.queryParameters['mode'] ?? 'seasonal',
            part: int.tryParse(state.uri.queryParameters['part'] ?? ''),
            initialTitle: test?.displayName.isNotEmpty == true
                ? test!.displayName
                : test?.name,
          );
        },
      ),
      GoRoute(
          path: '/history', builder: (context, state) => const HistoryPage()),
      GoRoute(
        path: '/history/:recordId',
        builder: (context, state) => RecordDetailPage(
          recordId: int.tryParse(state.pathParameters['recordId'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/feedback/:recordId/:detailId',
        builder: (context, state) => FeedbackPage(
          recordId: int.tryParse(state.pathParameters['recordId'] ?? '') ?? 0,
          detailId: int.tryParse(state.pathParameters['detailId'] ?? '') ?? 0,
          source: state.uri.queryParameters['from'] ?? 'history',
        ),
      ),
    ],
    errorBuilder: (context, state) => const TopicSelectionPage(),
  );
}

class PageChangeObserver extends NavigatorObserver {
  PageChangeObserver(this.onPageChanged);

  final VoidCallback onPageChanged;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (previousRoute != null && route is PageRoute<dynamic>) {
      onPageChanged();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute<dynamic>) onPageChanged();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (route is PageRoute<dynamic>) onPageChanged();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute is PageRoute<dynamic> || oldRoute is PageRoute<dynamic>) {
      onPageChanged();
    }
  }
}
