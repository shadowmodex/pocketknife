import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// The four tools, in the order shown on Home.
enum ToolKind { video, mp3, photo, docs }

extension ToolKindMeta on ToolKind {
  String get id => name;

  IconData get icon {
    switch (this) {
      case ToolKind.video:
        return Icons.play_circle_fill_rounded;
      case ToolKind.mp3:
        return Icons.music_note_rounded;
      case ToolKind.photo:
        return Icons.image_rounded;
      case ToolKind.docs:
        return Icons.description_rounded;
    }
  }

  Color get color {
    switch (this) {
      case ToolKind.video:
        return AppColors.toolVideo;
      case ToolKind.mp3:
        return AppColors.toolMp3;
      case ToolKind.photo:
        return AppColors.toolPhoto;
      case ToolKind.docs:
        return AppColors.toolDocs;
    }
  }

  Color get tileBg {
    switch (this) {
      case ToolKind.video:
        return AppColors.toolVideoBg;
      case ToolKind.mp3:
        return AppColors.toolMp3Bg;
      case ToolKind.photo:
        return AppColors.toolPhotoBg;
      case ToolKind.docs:
        return AppColors.toolDocsBg;
    }
  }

  String get title {
    switch (this) {
      case ToolKind.video:
        return 'Video Downloader';
      case ToolKind.mp3:
        return 'Clip2MP3';
      case ToolKind.photo:
        return 'Photo Resizer';
      case ToolKind.docs:
        return 'Docs Toolkit';
    }
  }

  String get blurb {
    switch (this) {
      case ToolKind.video:
        return 'YouTube, Shorts,\nInstagram & more';
      case ToolKind.mp3:
        return 'YouTube to MP3\nHigh quality audio';
      case ToolKind.photo:
        return 'Resize, convert\nand reduce size';
      case ToolKind.docs:
        return 'PDF, Word and more\nMerge, split, convert';
    }
  }

  String get route => '/$name';

  static ToolKind fromId(String id) =>
      ToolKind.values.firstWhere((t) => t.name == id, orElse: () => ToolKind.photo);
}

/// A completed piece of work, shown in Recent Activity and the Activity tab.
class ActivityItem {
  final String id;
  final ToolKind kind;
  final String name; // file name, e.g. song.mp3
  final String meta; // e.g. "320 kbps • 8.4 MB"
  final String? savedPath;
  final DateTime at;

  ActivityItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.meta,
    this.savedPath,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'meta': meta,
        'savedPath': savedPath,
        'at': at.millisecondsSinceEpoch,
      };

  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
        id: j['id'] as String,
        kind: ToolKindMeta.fromId(j['kind'] as String),
        name: j['name'] as String,
        meta: j['meta'] as String,
        savedPath: j['savedPath'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
}

enum JobStatus { running, completed, failed, paused }

/// A live download (video / mp3). Rendered with a progress bar; when it finishes
/// it also becomes an [ActivityItem].
class DownloadJob {
  final String id;
  final ToolKind kind;
  String title;
  String subtitle;
  double progress; // 0..1
  JobStatus status;
  String? error;
  String? savedPath;
  final DateTime startedAt;

  DownloadJob({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.progress = 0,
    this.status = JobStatus.running,
    this.error,
    this.savedPath,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();
}
