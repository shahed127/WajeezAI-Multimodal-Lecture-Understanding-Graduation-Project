import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TopBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool search;
  final Widget? action;
  const TopBar({super.key, required this.title, required this.subtitle, this.search = true, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ],
          ),
        ),
        if (search)
          Container(
            width: 260, height: 43,
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.border)),
            child: const TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search, size: 19),
                hintText: 'Search lectures, topics...',
                border: InputBorder.none,
              ),
            ),
          ),
        if (search) const SizedBox(width: 12),
        Container(
          width: 43, height: 43,
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.border)),
          child: const Icon(Icons.notifications_none_rounded, color: AppColors.muted),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}
