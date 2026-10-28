import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 初始化答题页“回看原文”引导是否已展示/跳过的 SharedPreferences 标记。
const String kInitQuizGuideSeenKey = 'init_quiz_guide_seen';

/// 初始化第一篇阅读操作教程是否已展示/跳过的 SharedPreferences 标记。
const String kInitTutorialSeenKey = 'init_tutorial_seen';

/// 一次性引导 seen 标记的读写契约。
///
/// 生产实现是 [PrefsOneShotGuideStore]（SharedPreferences）；单测可注入内存实现，
/// 从而不依赖 `SharedPreferences.setMockInitialValues` 直接验证编排时序。
abstract class OneShotGuideStore {
  Future<bool> isSeen(String key);

  Future<void> markSeen(String key);
}

/// 默认 seen 标记存储：SharedPreferences（key 契约由 [OneShotGuide.seenKey] 定义）。
class PrefsOneShotGuideStore implements OneShotGuideStore {
  const PrefsOneShotGuideStore();

  @override
  Future<bool> isSeen(String key) async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  @override
  Future<void> markSeen(String key) async {
    await (await SharedPreferences.getInstance()).setBool(key, true);
  }
}

/// 一次性引导浮层的编排：读 seen key → 插入 Overlay → 完成写 key / 仅移除。
///
/// 浮层内容由调用方以 [builder] 提供（widgets 侧只负责外观），页面只保留
/// “何时可能展示”与“完成/销毁”的调用。
class OneShotGuide {
  /// 单个引导的持久化标记（[OneShotGuideStore] 中的 key）。
  final String seenKey;

  final OneShotGuideStore _store;
  OverlayEntry? _entry;

  OneShotGuide({
    required this.seenKey,
    OneShotGuideStore store = const PrefsOneShotGuideStore(),
  }) : _store = store;

  /// 初始化答题页“回看原文”引导（seen key 归 engine）。
  factory OneShotGuide.initQuiz({
    OneShotGuideStore store = const PrefsOneShotGuideStore(),
  }) =>
      OneShotGuide(seenKey: kInitQuizGuideSeenKey, store: store);

  /// 初始化第一篇阅读操作教程（seen key 归 engine）。
  factory OneShotGuide.initTutorial({
    OneShotGuideStore store = const PrefsOneShotGuideStore(),
  }) =>
      OneShotGuide(seenKey: kInitTutorialSeenKey, store: store);

  /// 浮层当前是否已插入。
  bool get isShowing => _entry != null;

  /// 读 seen 标记（[force] 为 true 时不读），未看过则插入浮层并返回 true。
  ///
  /// 读取期间页面若已销毁（[context] 失效）则不插入，返回 false；
  /// 浮层已展示时直接返回 true（幂等）。
  Future<bool> maybeShow(
    BuildContext context, {
    required WidgetBuilder builder,
    bool force = false,
  }) async {
    if (_entry != null) return true;
    if (!force && await _store.isSeen(seenKey)) return false;
    if (!context.mounted) return false;
    _entry = OverlayEntry(builder: builder);
    Overlay.of(context).insert(_entry!);
    return true;
  }

  /// 步进后重绘浮层内容（步骤推进由调用方状态驱动）。
  void refresh() => _entry?.markNeedsBuild();

  /// 完成/跳过：写 seen 标记后移除浮层。
  Future<void> finish() async {
    await _store.markSeen(seenKey);
    dismiss();
  }

  /// 仅移除浮层（例如页面销毁），不写标记。
  void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}
