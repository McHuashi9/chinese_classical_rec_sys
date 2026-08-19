library;

import 'lunar_calendar.dart';

/// 传统农历节日注册表。
///
/// 后续增加春节/端午/中秋等只需在 [_festivals] 中登记农历月日与展示数据，
/// 不需要改换算核心。
class Festival {
  final String id;
  final int lunarMonth;
  final int lunarDay;
  final String title;
  final String subtitle;
  final String content;

  const Festival({
    required this.id,
    required this.lunarMonth,
    required this.lunarDay,
    required this.title,
    required this.subtitle,
    required this.content,
  });
}

/// 已注册的农历节日。
const List<Festival> _festivals = [
  Festival(
    id: 'qixi',
    lunarMonth: 7,
    lunarDay: 7,
    title: '七夕快乐',
    subtitle: '农历七月初七 · 鹊桥仙·纤云弄巧',
    content: '纤云弄巧，飞星传恨，银汉迢迢暗度。\n'
        '金风玉露一相逢，便胜却人间无数。\n'
        '柔情似水，佳期如梦，忍顾鹊桥归路。\n'
        '两情若是久长时，又岂在朝朝暮暮。',
  ),
];

/// 返回公历 [now] 当天命中的农历节日；没有则返回 `null`。
Festival? festivalForToday(DateTime now) {
  for (final festival in _festivals) {
    if (isLunarFestivalToday(now, festival.lunarMonth, festival.lunarDay)) {
      return festival;
    }
  }
  return null;
}
