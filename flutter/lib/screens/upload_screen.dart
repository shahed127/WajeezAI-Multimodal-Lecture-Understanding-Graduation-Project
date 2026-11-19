import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/top_bar.dart';

class UploadScreen extends StatefulWidget {
  final ValueChanged<String> onUploaded;
  const UploadScreen({super.key, required this.onUploaded});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _api = const ApiService();
  PlatformFile? audio;
  final List<PlatformFile> slides = [];
  final title = TextEditingController();

  /// slide filename -> timestamp (seconds into the audio when that slide
  /// appeared). This is exactly the `timestamps.json` shape the backend
  /// expects.
  final Map<String, TextEditingController> slideTimestamps = {};

  bool submitting = false;
  String? errorText;

  Future<void> pickAudio() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.audio, withData: true);
    if (r != null && r.files.isNotEmpty) {
      setState(() => audio = r.files.first);
    }
  }

  Future<void> pickSlides() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true, withData: true);
    if (r != null) {
      setState(() {
        for (final f in r.files) {
          if (slides.any((s) => s.name == f.name)) continue;
          slides.add(f);
          final defaultTs = (slideTimestamps.length * 30).toString();
          slideTimestamps[f.name] = TextEditingController(text: defaultTs);
        }
      });
    }
  }

  void removeSlide(PlatformFile f) {
    setState(() {
      slides.remove(f);
      slideTimestamps.remove(f.name)?.dispose();
    });
  }

  Future<void> submit() async {
    if (audio == null) {
      setState(() => errorText = 'Please choose an audio recording.');
      return;
    }
    if (slides.isEmpty) {
      setState(() => errorText = 'Please choose at least one whiteboard/slide image.');
      return;
    }

    final timestamps = <String, double>{};
    for (final s in slides) {
      final raw = slideTimestamps[s.name]?.text.trim() ?? '';
      final parsed = double.tryParse(raw);
      if (parsed == null) {
        setState(() => errorText = 'Timestamp for "${s.name}" must be a number of seconds.');
        return;
      }
      timestamps[s.name] = parsed;
    }

    setState(() {
      submitting = true;
      errorText = null;
    });

    try {
      final lectureId = await _api.uploadLecture(
        audio: audio!,
        slides: slides,
        timestamps: timestamps,
        title: title.text.trim().isEmpty ? null : title.text.trim(),
      );
      await _api.processLecture(lectureId);
      await lectureStore.refresh();
      if (!mounted) return;
      widget.onUploaded(lectureId);
    } catch (e) {
      setState(() => errorText = 'Upload failed: $e');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  void dispose() {
    for (final c in slideTimestamps.values) {
      c.dispose();
    }
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(34, 28, 34, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TopBar(
                title: 'Upload New Lecture',
                subtitle: 'Add your lecture audio and slides — the AI will align, transcribe and write the notes.',
                search: false,
              ),
              const SizedBox(height: 24),
              _field('Lecture title (optional)', 'Neural Networks', title),
              const SizedBox(height: 20),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _audioBox()),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: _slidesBox()),
              ]),
              const SizedBox(height: 20),
              if (errorText != null) ...[
                Text(errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                const SizedBox(height: 12),
              ],
              AppCard(
                child: Row(children: [
                  const Icon(Icons.auto_awesome, color: AppColors.purple2),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('What happens next?', style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 4),
                        Text(
                          'Speech-to-text, OCR, semantic alignment between audio and slides, and a final .docx (convertible to PDF) are generated automatically.',
                          style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  AppGradientButton(
                    label: submitting ? 'Uploading...' : 'Start Processing',
                    icon: Icons.play_arrow_rounded,
                    onPressed: submitting ? null : submit,
                  ),
                ]),
              ),
            ],
          ),
        ),
      );

  Widget _field(String label, String hint, TextEditingController c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          TextField(controller: c, decoration: InputDecoration(hintText: hint)),
        ],
      );

  Widget _audioBox() => AppCard(
        child: Column(children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.purple2.withOpacity(.1),
              border: Border.all(color: AppColors.purple2.withOpacity(.35)),
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: AppColors.purple2, size: 27),
          ),
          const SizedBox(height: 14),
          const Text('Audio Recording', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          const Text('MP3, WAV, M4A — one file', style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
          const SizedBox(height: 17),
          OutlinedButton.icon(
            onPressed: pickAudio,
            icon: const Icon(Icons.folder_open_rounded, size: 17),
            label: const Text('Choose File'),
          ),
          if (audio != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.check_circle, color: AppColors.purple2, size: 14),
              const SizedBox(width: 5),
              Expanded(
                  child: Text(audio!.name,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: AppColors.muted))),
            ]),
          ],
        ]),
      );

  Widget _slidesBox() => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cyan.withOpacity(.1),
                border: Border.all(color: AppColors.cyan.withOpacity(.35)),
              ),
              child: const Icon(Icons.image_outlined, color: AppColors.cyan, size: 27),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Whiteboard / Slide Images', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  const Text('JPG, PNG — pick multiple, then set when each appears (seconds into the audio)',
                      style: TextStyle(color: AppColors.muted, fontSize: 10.5)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: pickSlides,
                    icon: const Icon(Icons.folder_open_rounded, size: 17),
                    label: const Text('Choose Files'),
                  ),
                ],
              ),
            ),
          ]),
          if (slides.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.border),
            const SizedBox(height: 8),
            ...slides.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const Icon(Icons.image, color: AppColors.cyan, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(f.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: slideTimestamps[f.name],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          isDense: true,
                          suffixText: 's',
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => removeSlide(f),
                      icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.muted),
                    ),
                  ]),
                )),
          ],
        ]),
      );
}
