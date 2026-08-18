/// 通用农历换算（支持 2000–2100）。
///
/// 数据来源为通用 1900–2100 农历信息表；对外只开放 2000–2100，
/// 超出范围返回 `null` / `false`，不抛异常。
library;

/// 农历日期。
class LunarDate {
  final int year;
  final int month;
  final int day;
  final bool isLeap;

  const LunarDate({
    required this.year,
    required this.month,
    required this.day,
    this.isLeap = false,
  });
}

const int _minLunarYear = 2000;
const int _maxLunarYear = 2100;

/// 农历 1900–2100 年信息表（标准数据，位运算含义与常见农历算法一致）。
const List<int> _lunarInfo = [
  0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,
  0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,
  0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,
  0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
  0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,
  0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8, 0x0e950, 0x06aa0,
  0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,
  0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b6a0, 0x195a6,
  0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
  0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x05ac0, 0x0ab60, 0x096d5, 0x092e0,
  0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,
  0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
  0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
  0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45,
  0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
  0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20, 0x1a6c4, 0x0aae0,
  0x092e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0, 0x0a6d0, 0x055d4,
  0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4, 0x0a5b0, 0x052b0,
  0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570, 0x054e4, 0x0d160,
  0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a4d0, 0x0d150, 0x0f252,
  0x0d520,
];

int _leapMonth(int year) => _lunarInfo[year - 1900] & 0xf;

int _leapDays(int year) {
  if (_leapMonth(year) == 0) return 0;
  return (_lunarInfo[year - 1900] & 0x10000) != 0 ? 30 : 29;
}

int _monthDays(int year, int month) {
  if (month < 1 || month > 12) return -1;
  return (_lunarInfo[year - 1900] & (0x10000 >> month)) != 0 ? 30 : 29;
}

int _lYearDays(int year) {
  var sum = 348;
  final info = _lunarInfo[year - 1900];
  for (var i = 0x8000; i >= 0x10; i >>= 1) {
    if ((info & i) != 0) sum++;
  }
  return sum + _leapDays(year);
}

/// 农历转公历；超出 2000–2100 或参数非法返回 `null`。
DateTime? lunarToSolar(LunarDate date) {
  final y = date.year;
  if (y < _minLunarYear || y > _maxLunarYear) return null;
  if (date.month < 1 || date.month > 12) return null;

  final leap = _leapMonth(y);
  if (date.isLeap && leap != date.month) return null;

  final days = date.isLeap ? _leapDays(y) : _monthDays(y, date.month);
  if (date.day < 1 || date.day > days) return null;
  // 表数据覆盖到 2100 年农历十二月一日。
  if (y == 2100 && date.month == 12 && date.day > 1) return null;

  var offset = 0;
  for (var i = 1900; i < y; i++) {
    offset += _lYearDays(i);
  }

  var isAdd = false;
  for (var i = 1; i < date.month; i++) {
    if (!isAdd) {
      final m = _leapMonth(y);
      if (m <= i && m > 0) {
        offset += _leapDays(y);
        isAdd = true;
      }
    }
    offset += _monthDays(y, i);
  }
  if (date.isLeap) {
    offset += _monthDays(y, date.month);
  }

  // 1900 年农历正月初一对应公历 1900-01-31。
  final base = DateTime.utc(1900, 1, 31);
  return base.add(Duration(days: offset + date.day - 1));
}

/// 判断公历 [now] 当天是否为某农历节日（month/day 为农历月日）。
bool isLunarFestivalToday(DateTime now, int month, int day) {
  final solar = lunarToSolar(
    LunarDate(year: now.year, month: month, day: day),
  );
  if (solar == null) return false;
  return solar.year == now.year &&
      solar.month == now.month &&
      solar.day == now.day;
}
