import 'package:flutter/foundation.dart';

/// Global, runtime-editable configuration for the app.
///
/// [apiBaseUrl] points at the FastAPI backend (see `main.py`). It can be
/// changed from the Settings screen without rebuilding the app, which is
/// handy when the backend is deployed somewhere other than localhost.
class AppConfig {
  AppConfig._();

  /// Default assumes the FastAPI server is running locally on port 8000,
  /// e.g. `uvicorn main:app --reload`.
  static final ValueNotifier<String> apiBaseUrl =
      ValueNotifier<String>('http://127.0.0.1:8000');

  static String get base {
    final v = apiBaseUrl.value;
    return v.endsWith('/') ? v.substring(0, v.length - 1) : v;
  }
}
