import 'package:flutter/material.dart';

import 'package:chinese_classical_rec_sys/theme/theme.dart';

/// 档案首字色块头像：按档案 id 稳定取色，显示档案名首字。
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    required this.id,
    this.radius = 16,
  });

  final String name;
  final int id;
  final double radius;

  @override
  Widget build(BuildContext context) {
    const colors = AppTheme.profileAvatarColors;
    final background = colors[id % colors.length];
    final firstChar =
        name.isEmpty ? '?' : String.fromCharCode(name.runes.first);
    final foreground =
        background.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    return CircleAvatar(
      radius: radius,
      backgroundColor: background,
      child: Text(
        firstChar,
        style: TextStyle(
          color: foreground,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
