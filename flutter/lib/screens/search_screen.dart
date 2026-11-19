import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';

class SearchScreen extends StatefulWidget {
  final ValueChanged<String> onOpen;
  const SearchScreen({super.key, required this.onOpen});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lectureStore,
      builder: (context, _) {
        final results = lectureStore.lectures
            .where((l) => (l.title + l.status).toLowerCase().contains(q.toLowerCase()))
            .toList();

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(34, 28, 34, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Search', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const Text('Search across your lectures by title or status.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 24),
                TextField(
                  onChanged: (value) => setState(() => q = value),
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Try a lecture title, e.g. "Neural Networks"...',
                  ),
                ),
                const SizedBox(height: 20),
                Text('${results.length} results', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView(
                    children: results.map((lecture) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: () => widget.onOpen(lecture.id),
                          borderRadius: BorderRadius.circular(20),
                          child: AppCard(
                            child: Row(
                              children: [
                                const Icon(Icons.picture_as_pdf_rounded, color: AppColors.purple2),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(lecture.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 4),
                                      Text(lecture.friendlyStatus,
                                          style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
