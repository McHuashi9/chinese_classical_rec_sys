library;

import 'lunar_calendar.dart';

/// 传统农历节日注册表。
///
/// 后续增加春节/端午/中秋等只需在此登记农历月日，不需要改换算核心。

/// 七夕：农历七月初七。
const int qixiMonth = 7;
const int qixiDay = 7;

/// 判断公历 [now] 当天是否为七夕。
bool isQixiToday(DateTime now) =>
    isLunarFestivalToday(now, qixiMonth, qixiDay);
