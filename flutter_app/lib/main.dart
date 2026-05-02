import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/app_state.dart';
import 'theme/theme.dart';

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

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // TODO: Sidebar (NavigationRail)
            Expanded(child: Center(child: Text('App Shell'))),
          ],
        ),
      ),
    );
  }
}
