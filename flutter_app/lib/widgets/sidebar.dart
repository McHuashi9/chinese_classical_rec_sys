import 'package:flutter/material.dart';
import 'package:chinese_classical_rec_sys/pages/library_page.dart';
import 'package:chinese_classical_rec_sys/pages/recommend_page.dart';
import 'package:chinese_classical_rec_sys/pages/read_page.dart';
import 'package:chinese_classical_rec_sys/pages/ability_page.dart';
import 'package:chinese_classical_rec_sys/pages/settings_page.dart';

/// 侧边导航 — 等价于 QML Sidebar，使用 Material 3 NavigationRail
class AppSidebar extends StatefulWidget {
  final void Function(Widget page)? onPageChanged;

  const AppSidebar({super.key, this.onPageChanged});

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  int _currentIndex = 0;

  static const _entries = <_NavEntry>[
    _NavEntry(Icons.library_books, '文库'),
    _NavEntry(Icons.recommend, '推荐'),
    _NavEntry(Icons.menu_book, '阅读'),
    _NavEntry(Icons.radar, '能力'),
    _NavEntry(Icons.settings, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      selectedIndex: _currentIndex,
      labelType: NavigationRailLabelType.all,
      onDestinationSelected: (i) {
        setState(() => _currentIndex = i);
      },
      destinations: _entries
          .map((e) => NavigationRailDestination(
                icon: Icon(e.icon),
                label: Text(e.label),
              ))
          .toList(),
    );
  }
}

class _NavEntry {
  final IconData icon;
  final String label;
  const _NavEntry(this.icon, this.label);
}
