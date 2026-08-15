/// 本地多用户档案（profiles 表行）
class UserProfile {
  final int id;
  final String name;
  final int createdAt;
  final int lastUsedAt;

  const UserProfile({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.lastUsedAt,
  });
}
