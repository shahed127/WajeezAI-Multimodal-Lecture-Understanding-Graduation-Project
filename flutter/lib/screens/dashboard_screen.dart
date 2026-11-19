import 'package:flutter/material.dart';
import '../main.dart';
import '../models/lecture.dart';
import '../theme/app_theme.dart';
import '../widgets/top_bar.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends StatelessWidget {
  final ValueChanged<String> onOpen;
  const DashboardScreen({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lectureStore,
      builder: (context, _) {
        final lectures = lectureStore.lectures;
        final ready = lectures.where((l) => l.status == 'processing_complete').length;
        final inProgress =
            lectures.where((l) => l.status == 'processing' || l.status == 'queued').length;
        final failed = lectures.where((l) => l.status == 'failed').length;
        final totalSeconds = lectures.fold<double>(0, (a, l) => a + l.durationSeconds);
        final totalHours = (totalSeconds / 3600);

        return _Frame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TopBar(
                title: 'Welcome back 👋',
                subtitle: 'Turn your lectures into organized study material.',
                action: IconButton(
                  tooltip: 'Refresh',
                  onPressed: lectureStore.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
              const SizedBox(height: 27),
              LayoutBuilder(builder: (_, c) {
                final cards = [
                  StatCard(
                    label: 'Lectures',
                    value: '${lectures.length}',
                    hint: 'Total uploaded',
                    icon: Icons.menu_book_rounded,
                    colors: const [AppColors.purple, AppColors.purple2],
                  ),
                  StatCard(
                    label: 'Study Hours',
                    value: '${totalHours.toStringAsFixed(1)}h',
                    hint: 'Total recorded time',
                    icon: Icons.access_time_rounded,
                    colors: const [AppColors.cyan, Color(0xFF4B8DFF)],
                  ),
                  StatCard(
                    label: 'Ready',
                    value: '$ready',
                    hint: 'Notes generated',
                    icon: Icons.auto_awesome_rounded,
                    colors: const [AppColors.pink, AppColors.purple],
                  ),
                  StatCard(
                    label: 'In Progress',
                    value: '$inProgress',
                    hint: failed > 0 ? '$failed failed' : 'Currently processing',
                    icon: Icons.folder_rounded,
                    colors: const [AppColors.green, AppColors.cyan],
                  ),
                ];
                return GridView.count(
                  crossAxisCount: c.maxWidth > 1000 ? 4 : 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.55,
                  children: cards,
                );
              }),
              const SizedBox(height: 24),
              LayoutBuilder(builder: (_, c) {
                final recent = _recent(context, lectures);
                final activity = _activity(lectures);
                if (c.maxWidth < 900) {
                  return Column(children: [recent, const SizedBox(height: 18), activity]);
                }
                return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: recent),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: activity),
                ]);
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _recent(BuildContext context, List<Lecture> lectures) {
    final items = lectures.take(6).toList();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: Text('Recent Lectures', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No lectures yet — upload one to get started.',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ...items.map((l) => InkWell(
              onTap: () => onOpen(l.id),
              borderRadius: BorderRadius.circular(15),
              child: Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(15)),
                child: Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      gradient: const LinearGradient(colors: [AppColors.purple, Color(0xFF44218F)]),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                        const SizedBox(height: 4),
                        Text('${l.numSlides} slides • ${l.durationLabel}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
                      ],
                    ),
                  ),
                  _Status(l),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ]),
              ),
            )),
      ]),
    );
  }

  Widget _activity(List<Lecture> lectures) {
    final inProgress =
        lectures.where((l) => l.status == 'processing' || l.status == 'queued').toList();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('AI Processing', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 17),
        if (inProgress.isEmpty)
          const Text('Nothing processing right now.', style: TextStyle(color: AppColors.muted, fontSize: 11.5))
        else
          ...inProgress.map((l) => _progress(l)),
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(14)),
          child: const Row(children: [
            Icon(Icons.auto_awesome, color: AppColors.purple2, size: 18),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Audio, whiteboard slides and files are combined and matched into one Word document.',
                style: TextStyle(fontSize: 10.5, color: AppColors.muted, height: 1.45),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _progress(Lecture l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(l.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
          Text(l.friendlyStatus, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: const LinearProgressIndicator(
            value: null,
            minHeight: 6,
            backgroundColor: const Color(0xFF202943),
            color: AppColors.purple2,
          ),
        ),
      ]),
    );
  }
}

class _Status extends StatelessWidget {
  final Lecture l;
  const _Status(this.l);
  @override
  Widget build(BuildContext context) {
    final ready = l.status == 'processing_complete';
    final failed = l.status == 'failed';
    final color = failed ? Colors.redAccent : (ready ? AppColors.green : AppColors.orange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.22)),
      ),
      child: Text(l.friendlyStatus, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }
}

class _Frame extends StatelessWidget {
  final Widget child;
  const _Frame({required this.child});
  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned(
          top: -100,
          left: 80,
          child: IgnorePointer(
            child: Container(
              width: 500,
              height: 300,
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [AppColors.purple.withOpacity(.14), Colors.transparent]),
              ),
            ),
          ),
        ),
        SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(34, 28, 34, 38), child: child)),
      ]);
}
