import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// 截图捕获函数签名，便于 widget 测试注入 mock。
typedef ScreenshotCapture = Future<String> Function();

/// 截取 [boundaryKey] 对应的整个应用界面并保存为 PNG。
///
/// 返回保存后的完整路径。目录为 `{应用支持目录}/screenshots/`，不存在时自动创建。
/// [outputDir] 仅用于测试注入；[pixelRatio] 不传时取当前设备像素比并限制在 1.0–2.0。
Future<String> captureAppScreenshot(
  GlobalKey boundaryKey, {
  double? pixelRatio,
  String? outputDir,
}) async {
  final boundaryContext = boundaryKey.currentContext;
  if (boundaryContext == null) {
    throw StateError('截图边界未就绪');
  }
  final boundary = boundaryContext.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('截图边界未就绪');
  }

  final ratio =
      (pixelRatio ?? _defaultPixelRatio(boundaryContext)).clamp(1.0, 2.0);
  await WidgetsBinding.instance.endOfFrame;
  final image = await boundary.toImage(pixelRatio: ratio);
  ByteData? byteData;
  try {
    byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  } finally {
    image.dispose();
  }
  if (byteData == null) {
    throw StateError('PNG 编码失败');
  }

  final dir = await ensureScreenshotDirectory(outputDir: outputDir);
  final path = '${dir.path}/${screenshotFileName(DateTime.now())}';
  await File(path).writeAsBytes(byteData.buffer.asUint8List());
  return path;
}

double _defaultPixelRatio(BuildContext context) {
  final fromMedia = MediaQuery.maybeOf(context)?.devicePixelRatio;
  if (fromMedia != null && fromMedia > 0) return fromMedia;
  return WidgetsBinding
          .instance.platformDispatcher.implicitView?.devicePixelRatio ??
      1.0;
}

/// 确保截图目录存在并返回该目录。
///
/// 默认在应用支持目录下创建 `screenshots/`；[outputDir] 可注入用于测试。
Future<Directory> ensureScreenshotDirectory({String? outputDir}) async {
  final root = outputDir ?? (await getApplicationSupportDirectory()).path;
  final dir = Directory('$root/screenshots');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// 生成截图文件名：`screenshot_yyyyMMdd_HHmmss_SSS.png`。
@visibleForTesting
String screenshotFileName(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  String three(int v) => v.toString().padLeft(3, '0');
  return 'screenshot_${time.year}${two(time.month)}${two(time.day)}_'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}_'
      '${three(time.millisecond)}.png';
}
