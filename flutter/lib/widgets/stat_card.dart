import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final String label, value, hint;
  final IconData icon;
  final List<Color> colors;
  const StatCard({super.key, required this.label, required this.value, required this.hint, required this.icon, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11.5))),
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(colors: colors),
                ),
                child: Icon(icon, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text(hint, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
        ],
      ),
    );
  }
}
