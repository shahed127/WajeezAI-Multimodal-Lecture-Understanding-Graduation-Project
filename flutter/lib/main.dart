import 'package:flutter/material.dart';
import 'models/lecture.dart';
import 'services/lecture_store.dart';
import 'theme/app_theme.dart';
import 'widgets/sidebar.dart';
import 'screens/dashboard_screen.dart';
import 'screens/lectures_screen.dart';
import 'screens/upload_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/lecture_result_screen.dart';

/// Single app-wide store, polling the backend for lecture status.
final LectureStore lectureStore = LectureStore();

void main() => runApp(const SmartLectureApp());

class SmartLectureApp extends StatelessWidget {
  const SmartLectureApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart Lecture Assistant',
      theme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  SidebarItem selected = SidebarItem.dashboard;
  String? openedLectureId;

  @override
  void initState() {
    super.initState();
    lectureStore.start();
  }

  void openLecture(String lectureId) => setState(() {
        openedLectureId = lectureId;
        selected = SidebarItem.lectures;
      });
  void closeLecture() => setState(() => openedLectureId = null);

  Widget content() {
    if (openedLectureId != null) {
      return LectureResultScreen(lectureId: openedLectureId!, onBack: closeLecture);
    }
    switch (selected) {
      case SidebarItem.dashboard:
        return DashboardScreen(onOpen: openLecture);
      case SidebarItem.lectures:
        return LecturesScreen(onOpen: openLecture);
      case SidebarItem.upload:
        return UploadScreen(onUploaded: openLecture);
      case SidebarItem.notes:
        return NotesScreen(onOpen: openLecture);
      case SidebarItem.search:
        return SearchScreen(onOpen: openLecture);
      case SidebarItem.settings:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(child: content()),
          AppSidebar(
            selected: selected,
            onSelect: (item) => setState(() {
              selected = item;
              openedLectureId = null;
            }),
          ),
        ],
      ),
    );
  }
}

// Re-exported so screens that only need the type don't need to import
// models/lecture.dart directly for this single symbol.
typedef LectureRef = Lecture;
