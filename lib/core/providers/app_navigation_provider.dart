import 'package:flutter/material.dart';

class AppNavigationProvider extends ChangeNotifier {
  int _currentIndex = 0;
  int _previousIndex = 0;

  int get currentIndex => _currentIndex;
  int get previousIndex => _previousIndex;

  void setTab(int index) {
    if (_currentIndex != index) {
      _previousIndex = _currentIndex;
      _currentIndex = index;
      notifyListeners();
    }
  }

  void goBack() {
    setTab(_previousIndex);
  }
}