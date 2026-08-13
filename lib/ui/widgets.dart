import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../core/providers.dart';
import 'design.dart';

class AppFrame extends StatelessWidget {
  const AppFrame({
    required this.body,
    this.title,
    this.onBack,
    this.actions,
    this.bottom,
    this.padding = const EdgeInsets.fromLTRB(18, 0, 18, 28),
    super.key,
  });

  final Widget body;
  final String? title;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final Widget? bottom;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.canvas,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Scaffold(
              appBar: title == null
                  ? null
                  : AppBar(
                      toolbarHeight: 52,
                      centerTitle: true,
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      backgroundColor: AppColors.background,
                      surfaceTintColor: Colors.transparent,
                      shape: const Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                      leadingWidth: 78,
                      leading: onBack == null
                          ? null
                          : TextButton.icon(
                              onPressed: onBack,
                              icon: const Icon(Icons.chevron_left, size: 22),
                              label: const Text('返回'),
                            ),
                      title: Text(
                        title!,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      actions: actions,
                    ),
              body: SafeArea(
                top: title == null,
                child: Padding(padding: padding, child: body),
              ),
              bottomNavigationBar: bottom == null
                  ? null
                  : SafeArea(
                      top: false,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xFAFFFFFF),
                          border:
                              Border(top: BorderSide(color: AppColors.border)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 11, 18, 12),
                          child: bottom,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.accent,
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      );
}

class StatePanel extends StatelessWidget {
  const StatePanel({
    required this.title,
    this.description,
    this.loading = false,
    this.action,
    this.onAction,
    super.key,
  });

  final String title;
  final String? description;
  final bool loading;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Icon(Icons.info_outline,
                      size: 42, color: AppColors.muted),
                ),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              if (description != null) ...[
                const SizedBox(height: 8),
                Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (action != null && onAction != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onAction, child: Text(action!)),
              ],
            ],
          ),
        ),
      );
}

class ScoreBadge extends StatelessWidget {
  const ScoreBadge(this.score, {super.key});

  final double? score;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            score?.toStringAsFixed(1) ?? '—',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              fontSize: 21,
            ),
          ),
          const SizedBox(width: 4),
          const Text('/ 9',
              style: TextStyle(fontSize: 10, color: AppColors.muted)),
        ],
      );
}

class AudioAction extends ConsumerWidget {
  const AudioAction({
    required this.audioKey,
    required this.url,
    required this.label,
    super.key,
  });

  final String audioKey;
  final String url;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(audioServiceProvider);
    return StreamBuilder<PlayerState>(
      stream: service.playerStateStream,
      builder: (context, snapshot) {
        final playing =
            service.activeKey == audioKey && (snapshot.data?.playing ?? false);
        return TextButton.icon(
          onPressed: url.isEmpty
              ? null
              : () async {
                  try {
                    await service.toggleUrl(audioKey, url);
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('音频播放失败：$error')),
                      );
                    }
                  }
                },
          icon: Icon(
              playing ? Icons.stop_circle_outlined : Icons.play_circle_outline),
          label: Text(playing ? '停止播放' : label),
        );
      },
    );
  }
}

class BootstrapGate extends ConsumerWidget {
  const BootstrapGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountBootstrapProvider);
    return account.when(
      data: (_) => child,
      loading: () => const AppFrame(
        body: StatePanel(title: '正在初始化试用账号', loading: true),
      ),
      error: (error, _) => AppFrame(
        body: StatePanel(
          title: '账号初始化失败',
          description: error.toString(),
          action: '重新加载',
          onAction: () => ref.invalidate(accountBootstrapProvider),
        ),
      ),
    );
  }
}

void goBackOr(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}
