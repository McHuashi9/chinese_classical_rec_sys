import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'theme/theme.dart';
import 'pages/library_page.dart';
import 'pages/recommend_page.dart';
import 'pages/read_page.dart';
import 'pages/ability_page.dart';
import 'pages/settings_page.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const ChineseClassicalRecSysApp(),
    ),
  );
}

class ChineseClassicalRecSysApp extends StatelessWidget {
  const ChineseClassicalRecSysApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '中国古文推荐系统',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: context.watch<AppState>().darkMode
          ? ThemeMode.dark
          : ThemeMode.light,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static final _pages = <Widget>[
    const LibraryPage(),
    const RecommendPage(),
    const ReadPage(),
    const AbilityPage(),
    const SettingsPage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      app.addListener(_onAppStateChanged);
      _initApp(app);
    });
  }

  Future<void> _initApp(AppState app) async {
    const dbPath = '../data/classical.db';
    await app.initialize(dbPath);
    if (!mounted) return;
    app.getRecommendations(10);
  }

  void _onAppStateChanged() {
    final app = context.read<AppState>();
    if (app.error != null) {
      final errorMsg = app.error!;
      app.clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    context.read<AppState>().removeListener(_onAppStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: app.pageIndex,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: app.switchPage,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.library_books),
                  label: Text('文库'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.recommend),
                  label: Text('推荐'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.menu_book),
                  label: Text('阅读'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.radar),
                  label: Text('能力'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings),
                  label: Text('设置'),
                ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: app.initialized
                  ? _pages[app.pageIndex]
                  : const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }
}
