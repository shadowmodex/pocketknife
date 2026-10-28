import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The white rounded container used everywhere content sits on the canvas.
class PkCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  const PkCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: content,
      ),
    );
  }
}

/// Rounded square icon "tile" with a tool's tinted background.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final double size;
  const IconTile({super.key, required this.icon, required this.color, required this.bg, this.size = 46});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.tile)),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Home tool tile: icon, title, one-line blurb, chevron.
class ToolCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String title;
  final String blurb;
  final VoidCallback onTap;
  const ToolCard({
    super.key,
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.blurb,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PkCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(icon: icon, color: color, bg: bg),
              const Spacer(),
              const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.faint),
            ],
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 3),
          Text(blurb,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// A completed item in Recent Activity / the Activity tab.
class ActivityRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String title;
  final String meta;
  final String time;
  final VoidCallback? onTap;
  const ActivityRow({
    super.key,
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.meta,
    required this.time,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            IconTile(icon: icon, color: color, bg: bg, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(meta, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(time, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// A short info/warning strip (e.g. "audio is saved as AAC/.m4a").
class InfoBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color? tint;
  const InfoBanner({super.key, required this.message, this.icon = Icons.info_outline_rounded, this.tint});

  @override
  Widget build(BuildContext context) {
    final c = tint ?? AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.ink.withValues(alpha: 0.8))),
          ),
        ],
      ),
    );
  }
}

/// Live download row with progress, used in the Downloads list and tool screens.
class JobCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String title;
  final String subtitle;
  final double progress; // 0..1
  final bool running;
  final bool failed;
  final bool completed;
  final VoidCallback? onOpen;
  final VoidCallback? onShare;
  final VoidCallback? onDismiss;
  const JobCard({
    super.key,
    required this.icon,
    required this.color,
    required this.bg,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.running,
    required this.failed,
    required this.completed,
    this.onOpen,
    this.onShare,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return PkCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(icon: icon, color: color, bg: bg, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: failed ? AppColors.danger : AppColors.muted)),
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.faint),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (running) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                minHeight: 6,
                backgroundColor: AppColors.track,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(progress > 0 ? '${(progress * 100).round()}%' : 'Preparing…',
                style: Theme.of(context).textTheme.labelSmall),
          ],
          if (completed && (onOpen != null || onShare != null)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onOpen != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Open'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.lineStrong),
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.control)),
                      ),
                    ),
                  ),
                if (onOpen != null && onShare != null) const SizedBox(width: 10),
                if (onShare != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onShare,
                      icon: const Icon(Icons.ios_share_rounded, size: 16),
                      label: const Text('Share'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: const BorderSide(color: AppColors.lineStrong),
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.control)),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Green success card shown after a document/photo operation completes.
class SavedResultCard extends StatelessWidget {
  final String title;
  final String detail;
  final String location;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  const SavedResultCard({
    super.key,
    required this.title,
    required this.detail,
    required this.location,
    required this.onOpen,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return PkCard(
      color: AppColors.successBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(detail,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink)),
          Text(location, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.lineStrong),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share_rounded, size: 16),
                  label: const Text('Share'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.lineStrong),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A dashed-ish "choose a file" drop target used by the doc tools.
class PickTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const PickTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.lineStrong, width: 1.4),
        ),
        child: Column(
          children: [
            IconTile(icon: icon, color: AppColors.toolDocs, bg: AppColors.toolDocsBg, size: 54),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
