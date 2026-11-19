import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum SidebarItem { dashboard, lectures, upload, notes, search,  settings }

class AppSidebar extends StatelessWidget {
  final SidebarItem selected;
  final ValueChanged<SidebarItem> onSelect;
  const AppSidebar({super.key, required this.selected, required this.onSelect});

  static const items = [
    (SidebarItem.dashboard, Icons.grid_view_rounded, 'Dashboard'),
    (SidebarItem.lectures, Icons.menu_book_rounded, 'My Lectures'),
    (SidebarItem.upload, Icons.cloud_upload_rounded, 'Upload Lecture'),
    (SidebarItem.notes, Icons.notes_rounded, 'Notes & Summaries'),
    (SidebarItem.search, Icons.search_rounded, 'Search'),
    (SidebarItem.settings, Icons.settings_rounded, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 238,
      decoration: const BoxDecoration(
        color: Color(0xFF080D1C),
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
              child: Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: [AppColors.purple, AppColors.cyan]),
                      boxShadow: [BoxShadow(color: AppColors.purple.withOpacity(.35), blurRadius: 22)],
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Smart Lecture', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('AI Student Assistant', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final active = selected == item.$1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(13),
                      onTap: () => onSelect(item.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          gradient: active ? const LinearGradient(colors: [Color(0xFF43209B), Color(0xFF25145D)]) : null,
                          border: Border.all(color: active ? AppColors.purple.withOpacity(.45) : Colors.transparent),
                        ),
                        child: Row(
                          children: [
                            Icon(item.$2, size: 19, color: active ? Colors.white : AppColors.muted),
                            const SizedBox(width: 11),
                            Expanded(child: Text(item.$3, style: TextStyle(fontSize: 12.5, color: active ? Colors.white : AppColors.muted, fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(radius: 19, backgroundColor: AppColors.purple, child: Text('T', style: TextStyle(fontWeight: FontWeight.w800))),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tamara', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                        SizedBox(height: 3),
                        Text('Student', style: TextStyle(color: AppColors.muted, fontSize: 10)),
                      ],
                    ),
                  ),
                  Icon(Icons.more_horiz, color: AppColors.muted, size: 19),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
