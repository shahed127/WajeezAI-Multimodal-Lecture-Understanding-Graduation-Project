import 'package:flutter/material.dart';
import '../main.dart';
import '../models/lecture.dart';
import '../services/api_service.dart';
import '../services/download_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/top_bar.dart';

class LecturesScreen extends StatefulWidget {
  final ValueChanged<String> onOpen;
  const LecturesScreen({super.key, required this.onOpen});

  @override
  State<LecturesScreen> createState() => _LecturesScreenState();
}

class _LecturesScreenState extends State<LecturesScreen> {
  final _api = const ApiService();
  String query = '';
  String filter = 'All';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lectureStore,
      builder: (context, _) {
        var lectures = lectureStore.lectures;
        if (query.isNotEmpty) {
          lectures = lectures.where((l) => l.title.toLowerCase().contains(query.toLowerCase())).toList();
        }
        if (filter != 'All') {
          final map = {
            'Ready': 'processing_complete',
            'Processing': 'processing',
            'Queued': 'queued',
            'Failed': 'failed',
          };
          lectures = lectures.where((l) => l.status == map[filter]).toList();
        }

        return _Frame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TopBar(title: 'My Lectures', subtitle: 'All processed lecture notes in one place.', search: false),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search), hintText: 'Search by lecture title...'),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: filter,
                  underline: const SizedBox(),
                  items: const ['All', 'Ready', 'Processing', 'Queued', 'Failed']
                      .map((f) => DropdownMenuItem(value: f, child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(f),
                          )))
                      .toList(),
                  onChanged: (v) => setState(() => filter = v ?? 'All'),
                ),
                const SizedBox(width: 12),
                IconButton(onPressed: lectureStore.refresh, icon: const Icon(Icons.refresh_rounded)),
              ]),
              const SizedBox(height: 18),
              if (lectureStore.lastError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text('Could not reach backend: ${lectureStore.lastError}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                ),
              if (lectures.isEmpty)
                const AppCard(
                    child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                            child: Text('No lectures found.', style: TextStyle(color: AppColors.muted)))))
              else
                AppCard(child: Column(children: lectures.map((l) => _tile(context, l)).toList())),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, Lecture l) {
    final ready = l.status == 'processing_complete';
    final failed = l.status == 'failed';
    final color = failed ? Colors.redAccent : (ready ? AppColors.green : AppColors.orange);
    return InkWell(
      onTap: () => widget.onOpen(l.id),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(children: [
          Container(
            width: 52,
            height: 60,
            decoration:
                BoxDecoration(color: const Color(0xFF26152E), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFFF6575)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text('${l.numSlides} slides • ${l.durationLabel} • ${l.createdAtDate.toLocal().toString().split(".").first}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: color.withOpacity(.1), borderRadius: BorderRadius.circular(20)),
            child: Text(l.friendlyStatus, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 15),
          if (l.canDownloadDocx)
            IconButton(
              tooltip: 'Download .docx',
              onPressed: () => openDownload(_api.downloadDocxUrl(l.id)),
              icon: const Icon(Icons.download_rounded, color: AppColors.muted),
            ),
          const SizedBox(width: 3),
          const Icon(Icons.chevron_right, color: AppColors.muted),
        ]),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  final Widget child;
  const _Frame({required this.child});
  @override
  Widget build(BuildContext c) =>
      SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(34, 28, 34, 40), child: child));
}
