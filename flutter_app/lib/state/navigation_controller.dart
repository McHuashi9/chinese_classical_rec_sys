import 'package:flutter/foundation.dart';

class NavigationController extends ChangeNotifier {
  int _pageIndex = 0;
  int _previousPageIndex = 0;

  int get pageIndex => _pageIndex;
  int get previousPageIndex => _previousPageIndex;

  void switchPage(int index) {
    if (_pageIndex != index) {
      _previousPageIndex = _pageIndex;
      _pageIndex = index;
      notifyListeners();
    }
  }
}
