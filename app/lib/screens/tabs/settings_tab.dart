import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/cards.dart';
import '../../widgets/logo.dart';
import '../../widgets/scaffold.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      physics: const BouncingScrollPhysics(),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        const SectionHeader('Files & Storage'),
        PkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SwitchRow(
                icon: Icons.photo_library_rounded,
                title: 'Save to device library',
                subtitle: 'Automatically copy converted images to Pictures',
                value: store.saveToGallery,
                onChanged: store.setSaveToGallery,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeader('About'),
        PkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BrandLogo(size: 44),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pocketknife', style: Theme.of(context).textTheme.titleMedium),
                      Text('Version 1.0.0', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Everyday file tools that run entirely on your device. '
                'Fast, simple, and 100% offline. Nothing you convert is ever uploaded to a server.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'by Irshad Akhtar',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.faint, letterSpacing: 0.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
