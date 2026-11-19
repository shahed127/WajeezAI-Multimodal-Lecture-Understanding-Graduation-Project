import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config.dart';
import '../models/lecture.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Thin wrapper around the FastAPI backend described in `main.py`.
/// Implements all seven endpoints:
///   1. POST /api/lectures/upload
///   2. POST /api/lectures/{id}/process
///   3. GET  /api/lectures/{id}/status
///   4. GET  /api/lectures/{id}/download
///   5. GET  /api/lectures
///   6. POST /api/lectures/{id}/convert-pdf
///   7. GET  /api/lectures/{id}/download-pdf
class ApiService {
  const ApiService();

  String get _base => AppConfig.base;

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return {};
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    String detail = res.body;
    try {
      final j = jsonDecode(res.body);
      if (j is Map && j['detail'] != null) detail = j['detail'].toString();
    } catch (_) {}
    throw ApiException(detail, statusCode: res.statusCode);
  }

  // ------------------------------------------------------------------
  // 1. Upload
  // ------------------------------------------------------------------
  /// Uploads the lecture audio, slide images and a timestamps map.
  /// [timestamps] must be keyed by the *filename* of each slide in
  /// [slides] (matching what the backend expects in timestamps.json).
  Future<String> uploadLecture({
    required PlatformFile audio,
    required List<PlatformFile> slides,
    required Map<String, double> timestamps,
    String? title,
  }) async {
    final uri = Uri.parse('$_base/api/lectures/upload').replace(
      queryParameters: title != null && title.isNotEmpty ? {'title': title} : null,
    );
    final request = http.MultipartRequest('POST', uri);

    if (audio.bytes == null) {
      throw ApiException('Audio file has no data (bytes) to upload.');
    }
    request.files.add(http.MultipartFile.fromBytes(
      'audio',
      audio.bytes!,
      filename: audio.name,
    ));

    for (final slide in slides) {
      if (slide.bytes == null) continue;
      request.files.add(http.MultipartFile.fromBytes(
        'slides',
        slide.bytes!,
        filename: slide.name,
      ));
    }

    final timestampsJson = jsonEncode(timestamps);
    request.files.add(http.MultipartFile.fromBytes(
      'timestamps',
      utf8.encode(timestampsJson),
      filename: 'timestamps.json',
      contentType: MediaType('application', 'json'),
    ));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final j = _decode(res);
    return j['lecture_id'] as String;
  }

  // ------------------------------------------------------------------
  // 2. Process
  // ------------------------------------------------------------------
  Future<void> processLecture(String lectureId) async {
    final uri = Uri.parse('$_base/api/lectures/$lectureId/process');
    final res = await http.post(uri);
    _decode(res);
  }

  // ------------------------------------------------------------------
  // 3. Status
  // ------------------------------------------------------------------
  Future<Lecture> getStatus(String lectureId) async {
    final uri = Uri.parse('$_base/api/lectures/$lectureId/status');
    final res = await http.get(uri);
    return Lecture.fromStatusJson(_decode(res));
  }

  // ------------------------------------------------------------------
  // 4. Download docx (URL only - opened in the browser)
  // ------------------------------------------------------------------
  String downloadDocxUrl(String lectureId) =>
      '$_base/api/lectures/$lectureId/download';

  // ------------------------------------------------------------------
  // 5. List lectures
  // ------------------------------------------------------------------
  Future<List<Lecture>> listLectures() async {
    final uri = Uri.parse('$_base/api/lectures');
    final res = await http.get(uri);
    print("resresresresresres");
        print(res);

    final j = _decode(res);
    final list = (j['lectures'] as List<dynamic>? ?? [])
        .map((e) => Lecture.fromListJson(e as Map<String, dynamic>))
        .toList();
    return list;
  }

  // ------------------------------------------------------------------
  // 6. Convert to PDF
  // ------------------------------------------------------------------
  Future<void> convertToPdf(String lectureId) async {
    final uri = Uri.parse('$_base/api/lectures/$lectureId/convert-pdf');
    final res = await http.post(uri);
    _decode(res);
  }

  // ------------------------------------------------------------------
  // 7. Download PDF (URL only - opened in the browser)
  // ------------------------------------------------------------------
  String downloadPdfUrl(String lectureId) =>
      '$_base/api/lectures/$lectureId/download-pdf';

  /// Simple reachability check, used by the Settings screen.
  Future<bool> ping() async {
    try {
      final res = await http.get(Uri.parse('$_base/'));
      print("ronaldo");
      print(res);
      return res.statusCode == 200;
    } catch (e) {
      print(e);
      return false;
    }
  }
}
