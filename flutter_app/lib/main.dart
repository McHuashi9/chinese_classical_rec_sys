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
      themeMode: context.select((AppState a) => a.darkMode)
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

class _MainShellState extends State<MainShell> with TickerProviderStateMixin {
  static final _pages = <Widget>[
    const RepaintBoundary(child: LibraryPage()),
    const RepaintBoundary(child: RecommendPage()),
    const RepaintBoundary(child: ReadPage()),
    const RepaintBoundary(child: AbilityPage()),
    const RepaintBoundary(child: SettingsPage()),
  ];

  bool _initialized = false;
  int _pageIndex = 0;
  int _prevPageIndex = 0;
  bool _transitioning = false;
  AppState? _app;

  late final AnimationController _ctrl;
  late Animation<Offset> _slideOut;
  late Animation<Offset> _slideIn;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _transitioning = false);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _app = context.read<AppState>();
      _app!.addListener(_onAppStateChanged);
      _initApp(_app!);
    });
  }

  Future<void> _initApp(AppState app) async {
    const dbPath = '../data/classical.db';
    await app.initialize(dbPath);
    if (!mounted) return;
    app.getRecommendations(10);
  }

  void _onAppStateChanged() {
    final app = _app;
    if (app == null) return;
    if (app.error != null) {
      final errorMsg = app.error!;
      app.clearError();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (!_initialized && app.initialized) {
      setState(() => _initialized = true);
    }
    if (app.pageIndex != _pageIndex) {
      _prevPageIndex = _pageIndex;
      _pageIndex = app.pageIndex;
      _startTransition();
    }
  }

  void _startTransition() {
    final d = (_pageIndex > _prevPageIndex ? 1.0 : -1.0);
    _slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(-d * 0.08, 0),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart));
    _slideIn = Tween<Offset>(
      begin: Offset(d * 0.08, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutQuart));
    _transitioning = true;
    _ctrl.forward(from: 0.0);
  }

  void _onDestinationSelected(int index) {
    if (index == _pageIndex) return;
    _app?.switchPage(index);
  }

  @override
  void dispose() {
    _app?.removeListener(_onAppStateChanged);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _pageIndex,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: _onDestinationSelected,
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
              child: _initialized
                  ? _buildBody()
                  : const Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_transitioning) {
      return IndexedStack(index: _pageIndex, children: _pages);
    }
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: SlideTransition(position: _slideOut, child: _pages[_prevPageIndex]),
          ),
          Positioned.fill(
            child: SlideTransition(position: _slideIn, child: _pages[_pageIndex]),
          ),
        ],
      ),
    );
  }
}
