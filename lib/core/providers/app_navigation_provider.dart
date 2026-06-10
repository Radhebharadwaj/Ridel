import 'package:flutter/material.dart';

class AppNavigationProvider extends ChangeNotifier {
  int _currentIndex = 0;
  int _previousIndex = 0;
  bool _hasSeenNearestStopToast = false;
  
  Map<String, dynamic>? nearestMetroStation;
  Map<String, dynamic>? nearestBusStop;

  int get currentIndex => _currentIndex;
  int get previousIndex => _previousIndex;
  bool get hasSeenNearestStopToast => _hasSeenNearestStopToast;

  void markNearestStopToastSeen() {
    _hasSeenNearestStopToast = true;
    notifyListeners();
  }

  void setNearestMetroStation(Map<String, dynamic>? data) {
    nearestMetroStation = data;
    notifyListeners();
  }

  void setNearestBusStop(Map<String, dynamic>? data) {
    nearestBusStop = data;
    notifyListeners();
  }

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