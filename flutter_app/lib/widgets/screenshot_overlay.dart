import 'dart:io';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:chinese_classical_rec_sys/service/app_screenshot.dart';
import 'package:chinese_classical_rec_sys/state/screenshot_controller.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 截图模式根级确认浮层。
///
/// 浮层本身放在 `RepaintBoundary` 外，因此不会进入截图画面。
class ScreenshotConfirmOverlay extends StatefulWidget {
  const ScreenshotConfirmOverlay({
    super.key,
    required this.controller,
    required this.boundaryKey,
    required this.navigatorKey,
    required this.messengerKey,
    required this.onOpenFeedback,
    this.capture,
  });

  final ScreenshotController controller;
  final GlobalKey boundaryKey;
  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  /// 截图完成后通过 SnackBar 打开反馈时回调。
  final Future<void> Function(String path) onOpenFeedback;

  /// 可注入的捕获函数；为空时使用默认 [captureAppScreenshot]。
  final ScreenshotCapture? capture;

  @override
  State<ScreenshotConfirmOverlay> createState() =>
      _ScreenshotConfirmOverlayState();
}

class _ScreenshotConfirmOverlayState extends State<ScreenshotConfirmOverlay> {
  bool _capturing = false;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> _confirm() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final capture =
          widget.capture ?? () => captureAppScreenshot(widget.boundaryKey);
      final path = await capture();
      if (!mounted) return;
      widget.controller.complete(path);
      _showResult(path);
    } catch (e) {
      if (!mounted) return;
      _showError('截图失败：$e');
    } finally {
      if (mounted) {
        setState(() => _capturing = false);
      }
    }
  }

  void _cancel() => widget.controller.cancel();

  void _showResult(String path) {
    final messenger = widget.messengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '截图已保存到 $path',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: _isDesktop
                      ? () => _openDirectory(File(path).parent.path)
                      : () => _share(path),
                  child: Text(_isDesktop ? '打开截图目录' : '分享截图'),
                ),
                TextButton(
                  onPressed: () => _openFeedback(path),
                  child: const Text('附带反馈'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    final messenger = widget.messengerKey.currentState;
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openDirectory(String dir) async {
    widget.messengerKey.currentState?.hideCurrentSnackBar();
    try {
      final ok = await launchUrl(
        Uri.file(dir),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        _showError('无法打开截图目录');
      }
    } catch (e) {
      if (mounted) _showError('无法打开截图目录：$e');
    }
  }

  Future<void> _share(String path) async {
    widget.messengerKey.currentState?.hideCurrentSnackBar();
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          title: '文言文推荐系统截图',
        ),
      );
    } catch (e) {
      if (mounted) _showError('分享截图失败：$e');
    }
  }

  void _openFeedback(String path) {
    widget.messengerKey.currentState?.hideCurrentSnackBar();
    widget.onOpenFeedback(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Center(
          child: Material(
            color: context.appColors.cardBg,
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已开启截图模式，请切换到目标界面',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: context.appColors.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _capturing ? null : _cancel,
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _capturing ? null : _confirm,
                        icon: _capturing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.photo_camera, size: 18),
                        label: Text(_capturing ? '截取中…' : '确认截图'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
