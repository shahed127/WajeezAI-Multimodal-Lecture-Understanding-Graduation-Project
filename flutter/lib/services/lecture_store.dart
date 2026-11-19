import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/lecture.dart';
import 'api_service.dart';

/// Central, app-wide store for lecture data. Polls `GET /api/lectures`
/// every few seconds so every screen (dashboard, lectures list, search)
/// stays in sync without each one managing its own timer.
class LectureStore extends ChangeNotifier {
  LectureStore({ApiService? api}) : _api = api ?? const ApiService();

  final ApiService _api;
  List<Lecture> _lectures = [];
  bool loading = false;
  String? lastError;
  Timer? _timer;

  List<Lecture> get lectures => _lectures;

  Lecture? byId(String id) {
    for (final l in _lectures) {
      if (l.id == id) return l;
    }
    return null;
  }

  void start() {
    refresh();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      final result = await _api.listLectures();
      print('LectureStore.refresh: got ${result.length} lectures');
      _lectures = result;
      lastError = null;
    } catch (e) {
      lastError = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
