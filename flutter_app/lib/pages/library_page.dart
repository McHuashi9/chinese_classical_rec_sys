import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chinese_classical_rec_sys/state/app_state.dart';
import 'package:chinese_classical_rec_sys/theme/theme.dart';
import 'package:chinese_classical_rec_sys/widgets/library_card.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      setState(() => _filter = value.toLowerCase());
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final allTexts = app.texts;
    final filtered = allTexts.where((t) {
      if (_filter.isEmpty) return true;
      return t.title.toLowerCase().contains(_filter) ||
          t.author.toLowerCase().contains(_filter);
    }).toList();
    final isDark = app.darkMode;

    return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // header
              Row(
                children: [
                  Text('文库', style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(width: 8),
                  Text(
                    '(${filtered.length}篇)',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: AppTheme.fontBody,
                      color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: TextStyle(
                        fontSize: 16,
                        fontFamily: AppTheme.fontUI,
                        color: isDark ? AppTheme.darkInk : AppTheme.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: '搜索篇目或作者…',
                        hintStyle: TextStyle(
                          fontSize: 16,
                          fontFamily: AppTheme.fontUI,
                          color: isDark
                              ? AppTheme.darkInkSecondary
                              : AppTheme.inkSecondary,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                        border: const UnderlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.border),
                        ),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: AppTheme.vermilion, width: 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.border, height: 1),
              const SizedBox(height: 8),

              // list
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          '未找到匹配篇目',
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: AppTheme.fontUI,
                            color: isDark
                                ? AppTheme.darkInkSecondary
                                : AppTheme.inkSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, i) => _AnimatedListItem(
                          index: i,
                          child: LibraryCard(text: filtered[i]),
                        ),
                      ),
              ),
            ],
          ),
    );
  }
}

class _AnimatedListItem extends StatefulWidget {
  final int index;
  final Widget child;

  const _AnimatedListItem({required this.index, required this.child});

  @override
  State<_AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<_AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: Duration(milliseconds: 200 + widget.index * 30),
      vsync: this,
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: widget.child,
    );
  }
}
