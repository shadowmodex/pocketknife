import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/file_saver.dart';
import '../../services/store.dart';
import '../../util.dart';
import '../../widgets/cards.dart';
import '../../widgets/logo.dart';
import '../../widgets/scaffold.dart';
import '../video_screen.dart';
import '../mp3_screen.dart';
import '../photo_screen.dart';
import '../docs_screen.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  void _openTool(BuildContext context, ToolKind kind) {
    final Widget page = switch (kind) {
      ToolKind.video => const VideoScreen(),
      ToolKind.mp3 => const Mp3Screen(),
      ToolKind.photo => const PhotoScreen(),
      ToolKind.docs => const DocsScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final activeJobs =
        store.jobs.where((j) => j.status == JobStatus.running || j.status == JobStatus.failed).toList();
    final recent = store.activity.take(4).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                  Text('Pocketknife', style: Theme.of(context).textTheme.headlineSmall),
                  Text('Simple. Fast. Private.',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          _ToolGrid(onTap: (k) => _openTool(context, k)),
          if (activeJobs.isNotEmpty) ...[
            const SizedBox(height: 26),
            const SectionHeader('Downloads'),
            for (final job in activeJobs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: JobCard(
                  icon: job.kind.icon,
                  color: job.kind.color,
                  bg: job.kind.tileBg,
                  title: job.title,
                  subtitle: job.subtitle,
                  progress: job.progress,
                  running: job.status == JobStatus.running,
                  failed: job.status == JobStatus.failed,
                  completed: false,
                  onDismiss: () => store.removeJob(job),
                ),
              ),
          ],
          const SizedBox(height: 26),
          SectionHeader(
            'Recent activity',
            trailing: recent.isEmpty
                ? null
                : Text('Last ${recent.length}',
                    style: Theme.of(context).textTheme.labelSmall),
          ),
          if (recent.isEmpty)
            const EmptyState(
              icon: Icons.bolt_rounded,
              title: 'Nothing yet',
              message: 'Your converted files and downloads will show up here.',
            )
          else
            PkCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < recent.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    ActivityRow(
                      icon: recent[i].kind.icon,
                      color: recent[i].kind.color,
                      bg: recent[i].kind.tileBg,
                      title: recent[i].name,
                      meta: recent[i].meta,
                      time: timeAgo(recent[i].at),
                      onTap: recent[i].savedPath == null
                          ? null
                          : () => FileSaver.instance.open(recent[i].savedPath!),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolGrid extends StatelessWidget {
  final ValueChanged<ToolKind> onTap;
  const _ToolGrid({required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget cell(ToolKind k) => ToolCard(
          icon: k.icon,
          color: k.color,
          bg: k.tileBg,
          title: k.title,
          blurb: k.blurb.replaceAll('\n', ' '),
          onTap: () => onTap(k),
        );
    return Column(
      children: [
        Row(children: [
          Expanded(child: cell(ToolKind.video)),
          const SizedBox(width: 14),
          Expanded(child: cell(ToolKind.mp3)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: cell(ToolKind.photo)),
          const SizedBox(width: 14),
          Expanded(child: cell(ToolKind.docs)),
        ]),
      ],
    );
  }
}
