import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

/// 当前平台是否桌面。
///
/// 设置页的“打开日志目录 / 打开截图目录”仅桌面可用，
/// 移动端走分享路径；判据与 [defaultTargetPlatform] 一致（测试可覆写）。
bool get isDesktopPlatform =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS;
