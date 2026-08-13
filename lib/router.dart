import 'package:go_router/go_router.dart';

import 'core/models.dart';
import 'features/feedback_page.dart';
import 'features/history_page.dart';
import 'features/practice_page.dart';
import 'features/record_detail_page.dart';
import 'features/topic_selection_page.dart';

final appRouter = _createAppRouter();

GoRouter _createAppRouter() {
  // Imperative push routes must remain deep-linkable after a Web refresh.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  return GoRouter(
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
