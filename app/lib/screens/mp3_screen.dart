import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/download_error.dart';
import '../services/file_saver.dart';
import '../services/store.dart';
import '../services/youtube_service.dart';
import '../theme/app_colors.dart';
import '../widgets/cards.dart';
import '../widgets/controls.dart';
import '../widgets/scaffold.dart';

class Mp3Screen extends StatefulWidget {
  const Mp3Screen({super.key});
  @override
  State<Mp3Screen> createState() => _Mp3ScreenState();
}

class _Mp3ScreenState extends State<Mp3Screen> {
  final _urlCtl = TextEditingController();
  VideoMeta? _meta;
  bool _fetching = false;
  String? _error;
  String? _bitrate;
  String? _jobId;

  static const _options = [
    ('320', '320 kbps', 'Highest quality'),
    ('192', '192 kbps', 'Great for music'),
    ('128', '128 kbps', 'Smallest file'),
  ];

  @override
  void dispose() {
    _urlCtl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      _urlCtl.text = data!.text!.trim();
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final url = _urlCtl.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    final reason = YoutubeService.unsupportedReason(url);
    if (reason != null) {
      setState(() {
        _error = reason;
        _meta = null;
      });
      return;
    }
    setState(() {
      _fetching = true;
      _error = null;
      _meta = null;
    });
    try {
      final meta = await YoutubeService.instance.fetch(url);
      if (!mounted) return;
      setState(() => _meta = meta);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is DownloadException
            ? e.message
            : 'Couldn\'t read that link. Paste a YouTube video URL.');
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _download() async {
    final meta = _meta;
    if (meta == null) return;
    final store = context.read<AppStore>();
    final bitrate = _bitrate ?? store.audioBitrate;
    final job = store.startJob(ToolKind.mp3, meta.title, subtitle: 'Preparing…');
    setState(() => _jobId = job.id);
    try {
      final result = await YoutubeService.instance.downloadMp3(
        _urlCtl.text.trim(),
        bitrate,
        store.saveThumbnail,
        (p) => store.updateJob(job, progress: p),
        onStage: (s) => store.updateJob(job, subtitle: '$s…'),
      );
      final saved = await FileSaver.instance.saveAudio(result.tempPath, result.fileName);
      store.completeJob(job, meta: result.meta, savedPath: saved.path, name: result.fileName);
    } catch (e) {
      store.failJob(
          job, e is DownloadException ? e.message : 'Download failed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final bitrate = _bitrate ?? store.audioBitrate;
    final job = _jobId == null
        ? null
        : store.jobs
            .where((j) => j.id == _jobId)
            .cast<DownloadJob?>()
            .firstWhere((_) => true, orElse: () => null);
    final downloading = job?.status == JobStatus.running;

    return AppScaffold(
      title: 'Clip2MP3',
      subtitle: 'Extract high-quality audio',
      bottomBar: _meta == null
          ? null
          : PrimaryButton(
              label: 'Extract audio',
              icon: Icons.music_note_rounded,
              busy: downloading,
              onPressed: downloading ? null : _download,
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlCtl,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _fetch(),
                  decoration: const InputDecoration(
                    hintText: 'Paste a YouTube link',
                    prefixIcon: Icon(Icons.link_rounded, color: AppColors.faint, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: _fetching
                    ? const SizedBox(
                        width: 48,
                        child: Center(
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.4))))
                    : GhostButton(
                        label: 'Paste', icon: Icons.content_paste_rounded, onPressed: _paste),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_error != null)
            InfoBanner(
                message: _error!, icon: Icons.error_outline_rounded, tint: AppColors.danger),
          if (_meta != null) ...[
            PkCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      _meta!.thumbUrl,
                      width: 108,
                      height: 68,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 108,
                        height: 68,
                        color: AppColors.surfaceMuted,
                        child: const Icon(Icons.music_note_rounded, color: AppColors.faint),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_meta!.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                            '${_meta!.author}${_meta!.durationText.isNotEmpty ? ' • ${_meta!.durationText}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader('Audio quality'),
            PkCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < _options.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 46),
                    OptionTile(
                      title: _options[i].$2,
                      trailing: _options[i].$3,
                      selected: _options[i].$1 == bitrate,
                      recommended: _options[i].$1 == '320',
                      onTap: () => setState(() => _bitrate = _options[i].$1),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            const InfoBanner(
              message:
                  'Saved as a genuine MP3 (.mp3) with the title, artist, and cover art embedded — plays on any phone or music app.',
            ),
          ],
          if (job != null) ...[
            const SizedBox(height: 16),
            JobCard(
              icon: ToolKind.mp3.icon,
              color: ToolKind.mp3.color,
              bg: ToolKind.mp3.tileBg,
              title: job.title,
              subtitle: job.subtitle,
              progress: job.progress,
              running: job.status == JobStatus.running,
              failed: job.status == JobStatus.failed,
              completed: job.status == JobStatus.completed,
              onOpen:
                  job.savedPath == null ? null : () => FileSaver.instance.open(job.savedPath!),
              onShare:
                  job.savedPath == null ? null : () => FileSaver.instance.share(job.savedPath!),
            ),
          ],
        ],
      ),
    );
  }
}
