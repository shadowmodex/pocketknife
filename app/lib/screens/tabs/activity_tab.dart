import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/file_saver.dart';
import '../../services/store.dart';
import '../../theme/app_colors.dart';
import '../../util.dart';
import '../../widgets/cards.dart';
import '../../widgets/scaffold.dart';

class ActivityTab extends StatelessWidget {
  const ActivityTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final items = store.activity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
          child: Row(
            children: [
              Expanded(child: Text('Activity', style: Theme.of(context).textTheme.headlineSmall)),
              if (items.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _confirmClear(context, store),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                  label: const Text('Clear', style: TextStyle(color: AppColors.danger)),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  children: const [
                    EmptyState(
                      icon: Icons.history_rounded,
                      title: 'No activity yet',
                      message: 'Files you create, convert or download will appear here.',
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  physics: const BouncingScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final a = items[i];
                    return PkCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      child: ActivityRow(
                        icon: a.kind.icon,
                        color: a.kind.color,
                        bg: a.kind.tileBg,
                        title: a.name,
                        meta: a.meta,
                        time: timeAgo(a.at),
                        onTap: a.savedPath == null
                            ? null
                            : () => _openOrShare(context, a),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _openOrShare(BuildContext context, ActivityItem a) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.line, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded, color: AppColors.ink),
              title: const Text('Open'),
              onTap: () {
                Navigator.pop(context);
                FileSaver.instance.open(a.savedPath!);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded, color: AppColors.ink),
              title: const Text('Share'),
              onTap: () {
                Navigator.pop(context);
                FileSaver.instance.share(a.savedPath!, text: a.name);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context, AppStore store) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear activity?'),
        content: const Text('This removes the history list. Saved files stay on your device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              store.clearActivity();
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
