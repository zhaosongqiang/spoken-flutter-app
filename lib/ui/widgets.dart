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
    this.subtitle,
    this.onBack,
    this.actions,
    this.bottom,
    this.bottomColor = AppColors.background,
    this.bottomPadding = const EdgeInsets.fromLTRB(18, 10, 18, 12),
    this.padding = const EdgeInsets.fromLTRB(18, 0, 18, 28),
    super.key,
  });

  final Widget body;
  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final Widget? bottom;
  final Color bottomColor;
  final EdgeInsets bottomPadding;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: AppColors.canvas,
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: const BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: AppColors.border),
              ),
            ),
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
                      leadingWidth: 48,
                      leading: onBack == null
                          ? null
                          : IconButton(
                              tooltip: '返回',
                              onPressed: onBack,
                              icon: const Icon(Icons.chevron_left, size: 24),
                            ),
                      title: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontFamily: 'monospace',
                                fontSize: 10,
                                height: 1.3,
                              ),
                            ),
                        ],
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
                        decoration: BoxDecoration(
                          color: bottomColor,
                          border: const Border(
                            top: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: Padding(
                          padding: bottomPadding,
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
          color: AppColors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320, minHeight: 280),
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
                  Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        size: 24,
                        color: AppColors.foreground,
                      ),
                    ),
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
        ),
      );
}

class ScoreBadge extends StatelessWidget {
  const ScoreBadge(this.score, {this.pill = true, super.key});

  final double? score;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final label = '${score?.toStringAsFixed(1) ?? '—'} / 9';
    if (!pill) {
      return Text(
        label,
        style: const TextStyle(
          color: AppColors.muted,
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.muted,
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class AudioAction extends ConsumerWidget {
  const AudioAction({
    required this.audioKey,
    required this.url,
    required this.label,
    this.iconOnly = false,
    super.key,
  });

  final String audioKey;
  final String url;
  final String label;
  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(audioServiceProvider);
    return StreamBuilder<PlayerState>(
      stream: service.playerStateStream,
      builder: (context, snapshot) {
        final playing =
            service.activeKey == audioKey && (snapshot.data?.playing ?? false);
        Future<void> toggle() async {
          try {
            await service.toggleUrl(audioKey, url);
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('音频播放失败：$error')),
              );
            }
          }
        }

        if (iconOnly) {
          return Tooltip(
            message: playing ? '停止播放' : label,
            child: IconButton(
              onPressed: url.isEmpty ? null : toggle,
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
                fixedSize: const Size(44, 44),
                foregroundColor: AppColors.background,
                backgroundColor:
                    playing ? AppColors.accentHover : AppColors.accent,
                disabledForegroundColor: AppColors.background,
                disabledBackgroundColor: AppColors.border,
              ),
              icon:
                  Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
            ),
          );
        }
        return TextButton.icon(
          onPressed: url.isEmpty ? null : toggle,
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
