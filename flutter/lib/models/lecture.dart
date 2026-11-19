/// Mirrors the status dict returned by the FastAPI backend for a lecture
/// (see `/api/lectures` and `/api/lectures/{id}/status` in main.py).
class Lecture {
  final String id;
  final String title;
  final String status; // uploaded | queued | processing | processing_complete | failed
  final int numSlides;
  final double durationSeconds;
  final String? error;
  final double createdAt; // unix seconds
  final String? pdfStatus; // null | queued | converting | done | failed
  final String? pdfError;
  final bool canDownloadDocx;
  final bool canConvertPdf;
  final bool canDownloadPdf;

  const Lecture({
    required this.id,
    required this.title,
    required this.status,
    required this.numSlides,
    required this.durationSeconds,
    required this.createdAt,
    this.error,
    this.pdfStatus,
    this.pdfError,
    this.canDownloadDocx = false,
    this.canConvertPdf = false,
    this.canDownloadPdf = false,
  });

  factory Lecture.fromListJson(Map<String, dynamic> j) => Lecture(
        id: j['lecture_id'] as String,
        title: (j['title'] as String?) ?? j['lecture_id'] as String,
        status: j['status'] as String? ?? 'unknown',
        numSlides: (j['num_slides'] as num?)?.toInt() ?? 0,
        durationSeconds: (j['duration_seconds'] as num?)?.toDouble() ?? 0,
        error: j['error'] as String?,
        createdAt: (j['created_at'] as num?)?.toDouble() ?? 0,
        pdfStatus: j['pdf_status'] as String?,
        canDownloadDocx: j['can_download_docx'] as bool? ?? false,
        canConvertPdf: j['can_convert_pdf'] as bool? ?? false,
        canDownloadPdf: j['can_download_pdf'] as bool? ?? false,
      );

  /// The `/status` endpoint returns a slightly different (flatter) shape
  /// than the `/lectures` list endpoint, so it gets its own parser.
  factory Lecture.fromStatusJson(Map<String, dynamic> j) => Lecture(
        id: j['lecture_id'] as String,
        title: (j['title'] as String?) ?? j['lecture_id'] as String,
        status: j['status'] as String? ?? 'unknown',
        numSlides: (j['num_slides'] as num?)?.toInt() ?? 0,
        durationSeconds: (j['duration_seconds'] as num?)?.toDouble() ?? 0,
        error: j['error'] as String?,
        createdAt: (j['created_at'] as num?)?.toDouble() ?? 0,
        pdfStatus: j['pdf_status'] as String?,
        pdfError: j['pdf_error'] as String?,
        canDownloadDocx: j['status'] == 'processing_complete',
        canConvertPdf: j['status'] == 'processing_complete',
        canDownloadPdf: j['pdf_status'] == 'done',
      );

  String get friendlyStatus {
    switch (status) {
      case 'uploaded':
        return 'Uploaded';
      case 'queued':
        return 'Queued';
      case 'processing':
        return 'Processing';
      case 'processing_complete':
        return 'Ready';
      case 'failed':
        return 'Failed';
      default:
        return status;
    }
  }

  bool get isTerminal => status == 'processing_complete' || status == 'failed';

  DateTime get createdAtDate =>
      DateTime.fromMillisecondsSinceEpoch((createdAt * 1000).round());

  String get durationLabel {
    final total = durationSeconds.round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}
