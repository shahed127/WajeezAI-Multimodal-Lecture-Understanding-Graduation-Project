import 'dart:async';

import 'package:flutter/material.dart';
import '../main.dart';
import '../models/lecture.dart';
import '../services/api_service.dart';
import '../services/download_helper.dart';
import '../theme/app_theme.dart';

class LectureResultScreen extends StatefulWidget {
  final String lectureId;
  final VoidCallback onBack;
  const LectureResultScreen({super.key, required this.lectureId, required this.onBack});

  @override
  State<LectureResultScreen> createState() => _LectureResultScreenState();
}

class _LectureResultScreenState extends State<LectureResultScreen> {
  final _api = const ApiService();
  Lecture? lecture;
  Timer? _timer;
  bool convertingPdf = false;
  String? actionError;

  @override
  void initState() {
    super.initState();
    lecture = lectureStore.byId(widget.lectureId);
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final l = await _api.getStatus(widget.lectureId);
      if (mounted) setState(() => lecture = l);
      // Also nudge the global store so lists elsewhere stay fresh.
      lectureStore.refresh();
    } catch (e) {
      if (mounted) setState(() => actionError = 'Could not refresh status: $e');
    }
  }

  Future<void> _convertPdf() async {
    setState(() {
      convertingPdf = true;
      actionError = null;
    });
    try {
      await _api.convertToPdf(widget.lectureId);
      await _poll();
    } catch (e) {
      setState(() => actionError = 'PDF conversion failed: $e');
    } finally {
      if (mounted) setState(() => convertingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = lecture;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(34, 28, 34, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back_rounded, color: AppColors.muted)),
              const SizedBox(width: 4),
              const Text('My Lectures', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              const Text('  /  ', style: TextStyle(color: AppColors.muted)),
              Text(l?.title ?? widget.lectureId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (l != null && l.canDownloadDocx)
                OutlinedButton.icon(
                  onPressed: () => openDownload(_api.downloadDocxUrl(widget.lectureId)),
                  icon: const Icon(Icons.description_outlined, size: 17),
                  label: const Text('Download .docx'),
                ),
              const SizedBox(width: 10),
              if (l != null && l.canDownloadPdf)
                AppGradientButton(
                  label: 'Download PDF',
                  icon: Icons.download_rounded,
                  onPressed: () => openDownload(_api.downloadPdfUrl(widget.lectureId)),
                )
              else if (l != null && l.canConvertPdf)
                AppGradientButton(
                  label: convertingPdf ? 'Converting...' : 'Convert to PDF',
                  icon: Icons.picture_as_pdf_rounded,
                  onPressed: convertingPdf ? null : _convertPdf,
                ),
            ]),
            const SizedBox(height: 22),
            if (l == null)
              const AppCard(child: Padding(padding: EdgeInsets.all(20), child: Text('Loading lecture...')))
            else ...[
              _summaryCard(l),
              const SizedBox(height: 18),
              if (actionError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(actionError!, style: const TextStyle(color: Colors.redAccent, fontSize: 11.5)),
                ),
              _statusCard(l),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(Lecture l) => AppCard(
        child: Row(children: [
          Container(
            width: 64,
            height: 78,
            decoration: BoxDecoration(color: const Color(0xFF29152C), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFFF6875), size: 34),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('${l.numSlides} slides • ${l.durationLabel} • ${l.createdAtDate.toLocal().toString().split(".").first}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          _statusPill(l),
        ]),
      );

  Widget _statusPill(Lecture l) {
    final ready = l.status == 'processing_complete';
    final failed = l.status == 'failed';
    final color = failed ? Colors.redAccent : (ready ? AppColors.green : AppColors.orange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(20)),
      child: Text(l.friendlyStatus.toUpperCase(),
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  Widget _statusCard(Lecture l) {
    final steps = <(String, bool)>[
      ('Audio & slides uploaded', true),
      ('Transcription & OCR', l.status == 'processing' || l.isTerminal),
      ('Semantic alignment', l.status == 'processing_complete' || l.status == 'failed'),
      ('Word document generated', l.status == 'processing_complete'),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Processing Status', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          if (l.status == 'failed' && l.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(.08), borderRadius: BorderRadius.circular(12)),
                child: Text('Error: ${l.error}', style: const TextStyle(color: Colors.redAccent, fontSize: 11.5)),
              ),
            ),
          ...steps.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Icon(
                    s.$2 ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: s.$2 ? AppColors.green : AppColors.muted,
                    size: 17,
                  ),
                  const SizedBox(width: 9),
                  Expanded(child: Text(s.$1, style: const TextStyle(fontSize: 10.5))),
                ]),
              )),
          if (l.pdfStatus != null) ...[
            const Divider(color: AppColors.border, height: 26),
            Row(children: [
              const Icon(Icons.picture_as_pdf_rounded, color: AppColors.purple2, size: 17),
              const SizedBox(width: 9),
              Expanded(child: Text('PDF conversion: ${l.pdfStatus}', style: const TextStyle(fontSize: 10.5))),
            ]),
            if (l.pdfStatus == 'failed' && l.pdfError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l.pdfError!, style: const TextStyle(color: Colors.redAccent, fontSize: 10.5)),
              ),
          ],
        ],
      ),
    );
  }
}
