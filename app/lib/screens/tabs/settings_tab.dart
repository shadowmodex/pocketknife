import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/cards.dart';
import '../../widgets/logo.dart';
import '../../widgets/scaffold.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  static const _videoOptions = [
    ('best', 'Best available'),
    ('1080', '1080p'),
    ('720', '720p'),
    ('480', '480p'),
    ('360', '360p'),
  ];
  static const _audioOptions = [
    ('320', '320 kbps'),
    ('192', '192 kbps'),
    ('128', '128 kbps'),
  ];

  String _label(List<(String, String)> opts, String value) =>
      opts.firstWhere((o) => o.$1 == value, orElse: () => opts.first).$2;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      physics: const BouncingScrollPhysics(),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 20),
        const SectionHeader('Downloads'),
        PkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _NavRow(
                icon: Icons.high_quality_rounded,
                title: 'Default video quality',
                value: _label(_videoOptions, store.videoQuality),
                onTap: () => _pick(context, 'Video quality', _videoOptions, store.videoQuality,
                    store.setVideoQuality),
              ),
              const Divider(height: 1, indent: 54),
              _NavRow(
                icon: Icons.graphic_eq_rounded,
                title: 'Default audio quality',
                value: _label(_audioOptions, store.audioBitrate),
                onTap: () => _pick(context, 'Audio quality', _audioOptions, store.audioBitrate,
                    store.setAudioBitrate),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SectionHeader('Files'),
        PkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SwitchRow(
                icon: Icons.photo_library_rounded,
                title: 'Save media to gallery',
                subtitle: 'Also copy photos, video and audio to your device library',
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
                'Everyday file tools that run entirely on your device. Nothing you '
                'convert or download is uploaded to a server.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Center(
                child: Text('by Irshad Akhtar',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.faint, letterSpacing: 0.4)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _pick(
    BuildContext context,
    String title,
    List<(String, String)> options,
    String current,
    ValueChanged<String> onPick,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 6),
            for (final o in options)
              RadioListTile<String>(
                value: o.$1,
                groupValue: current,
                activeColor: AppColors.accent,
                title: Text(o.$2),
                onChanged: (v) {
                  if (v != null) onPick(v);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.title, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.muted),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
            Text(value, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.faint, size: 20),
          ],
        ),
      ),
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
            activeColor: AppColors.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
