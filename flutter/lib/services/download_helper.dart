import 'package:url_launcher/url_launcher.dart';

/// Opens a backend download URL (docx/pdf) in a new browser tab. The
/// backend sets `Content-Disposition: attachment` via FastAPI's
/// `FileResponse(filename=...)`, so the browser downloads the file
/// directly rather than navigating away from the app.
Future<bool> openDownload(String url) {
  final uri = Uri.parse(url);
  return launchUrl(uri, webOnlyWindowName: '_blank');
}
