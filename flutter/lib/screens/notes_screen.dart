import 'package:flutter/material.dart';
import '../main.dart';
import '../models/lecture.dart';
import '../services/api_service.dart';
import '../services/download_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/top_bar.dart';

class NotesScreen extends StatelessWidget {
  final ValueChanged<String> onOpen;
  const NotesScreen({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    const api = ApiService();
    return ListenableBuilder(
      listenable: lectureStore,
      builder: (context, _) {
        final ready = lectureStore.lectures.where((l) => l.status == 'processing_complete').toList();

        return _Frame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TopBar(
                title: 'Notes & AI Summaries',
                subtitle: 'Generated Word documents from your processed lectures.',
                search: false,
              ),
              const SizedBox(height: 24),
              if (ready.isEmpty)
                const AppCard(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                      child: Text('No finished notes yet. Upload a lecture to get started.',
                          style: TextStyle(color: AppColors.muted)),
                    ),
                  ),
                )
              else
                ...ready.map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: AppCard(
                        child: Row(children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              gradient: const LinearGradient(colors: [AppColors.purple, Color(0xFF44218F)]),
                            ),
                            child: const Icon(Icons.description_rounded, size: 21),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                                const SizedBox(height: 4),
                                Text('${l.numSlides} slides • ${l.durationLabel}',
                                    style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => onOpen(l.id),
                            icon: const Icon(Icons.visibility_outlined, size: 17),
                            label: const Text('View'),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Download .docx',
                            onPressed: () => openDownload(api.downloadDocxUrl(l.id)),
                            icon: const Icon(Icons.download_rounded, color: AppColors.muted),
                          ),
                        ]),
                      ),
                    )),
            ],
          ),
        );
      },
    );
  }
}

class _Frame extends StatelessWidget {
  final Widget child;
  const _Frame({required this.child});
  @override
  Widget build(BuildContext context) =>
      SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(34, 28, 34, 40), child: child));
}
