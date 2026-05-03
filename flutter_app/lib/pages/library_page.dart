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
    final allTexts = context.select((AppState a) => a.texts);
    final isDark = context.select((AppState a) => a.darkMode);
    final filtered = allTexts.where((t) {
      if (_filter.isEmpty) return true;
      return t.title.toLowerCase().contains(_filter) ||
          t.author.toLowerCase().contains(_filter);
    }).toList();

    return Padding(
          padding: EdgeInsets.all(context.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // header
              LayoutBuilder(
                builder: (ctx, constraints) {
                  if (constraints.maxWidth < 480) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('文库',
                            style: Theme.of(context).textTheme.headlineLarge,
                            overflow: TextOverflow.ellipsis),
                        SizedBox(height: context.gapSmall),
                        Text('(${filtered.length}篇)',
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: AppTheme.fontBody,
                              color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                            )),
                        SizedBox(height: context.gapMedium),
                        SizedBox(
                          width: double.infinity,
                          child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: '搜索篇目或作者…',
                            hintStyle: TextStyle(
                              fontSize: 16,
                              fontFamily: AppTheme.fontUI,
                              color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                            border: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.vermilion, width: 2)),
                          ),
                        ),
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Text(
                        '文库',
                        style: Theme.of(context).textTheme.headlineLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(width: context.gapMedium),
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
                            color: isDark ? AppTheme.darkInkSecondary : AppTheme.inkSecondary,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                          border: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.vermilion, width: 2)),
                        ),
                      ),
                      ),
                    ],
                  );
                },
              ),
              SizedBox(height: context.gapHuge),
              const Divider(color: AppTheme.border, height: 1),
              SizedBox(height: context.gapMedium),

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
                        itemBuilder: (ctx, i) => LibraryCard(text: filtered[i]),
                      ),
              ),
            ],
          ),
    );
  }
}
