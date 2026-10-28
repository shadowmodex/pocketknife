import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// App-wide state: user settings, the recent-activity log and live download jobs.
/// Activity and settings persist across launches; jobs are in-memory.
class AppStore extends ChangeNotifier {
  AppStore(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  static const _kActivity = 'pk.activity';
  static const _kVideoQuality = 'pk.video.quality';
  static const _kAudioBitrate = 'pk.audio.bitrate';
  static const _kSaveThumbnail = 'pk.audio.thumb';
  static const _kSaveToGallery = 'pk.saveGallery';

  // ---- settings ----
  String videoQuality = 'best'; // best | 1080 | 720 | 480 | 360
  String audioBitrate = '320'; // 320 | 192 | 128
  bool saveThumbnail = true;
  bool saveToGallery = true;

  // ---- data ----
  final List<ActivityItem> activity = [];
  final List<DownloadJob> jobs = [];

  void _load() {
    videoQuality = _prefs.getString(_kVideoQuality) ?? 'best';
    audioBitrate = _prefs.getString(_kAudioBitrate) ?? '320';
    saveThumbnail = _prefs.getBool(_kSaveThumbnail) ?? true;
    saveToGallery = _prefs.getBool(_kSaveToGallery) ?? true;
    final raw = _prefs.getString(_kActivity);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        activity
          ..clear()
          ..addAll(list.map(ActivityItem.fromJson));
      } catch (_) {}
    }
    notifyListeners();
  }

  void setVideoQuality(String v) {
    videoQuality = v;
    _prefs.setString(_kVideoQuality, v);
    notifyListeners();
  }

  void setAudioBitrate(String v) {
    audioBitrate = v;
    _prefs.setString(_kAudioBitrate, v);
    notifyListeners();
  }

  void setSaveThumbnail(bool v) {
    saveThumbnail = v;
    _prefs.setBool(_kSaveThumbnail, v);
    notifyListeners();
  }

  void setSaveToGallery(bool v) {
    saveToGallery = v;
    _prefs.setBool(_kSaveToGallery, v);
    notifyListeners();
  }

  // ---- activity ----
  void addActivity(ToolKind kind, String name, String meta, {String? savedPath}) {
    activity.insert(
      0,
      ActivityItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        kind: kind,
        name: name,
        meta: meta,
        savedPath: savedPath,
        at: DateTime.now(),
      ),
    );
    while (activity.length > 100) {
      activity.removeLast();
    }
    _persistActivity();
    notifyListeners();
  }

  void clearActivity() {
    activity.clear();
    _persistActivity();
    notifyListeners();
  }

  void _persistActivity() {
    _prefs.setString(_kActivity, jsonEncode(activity.map((e) => e.toJson()).toList()));
  }

  // ---- jobs ----
  DownloadJob startJob(ToolKind kind, String title, {String subtitle = ''}) {
    final job = DownloadJob(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      kind: kind,
      title: title,
      subtitle: subtitle,
    );
    jobs.insert(0, job);
    notifyListeners();
    return job;
  }

  void updateJob(DownloadJob job, {double? progress, String? subtitle, JobStatus? status}) {
    if (progress != null) job.progress = progress;
    if (subtitle != null) job.subtitle = subtitle;
    if (status != null) job.status = status;
    notifyListeners();
  }

  void completeJob(DownloadJob job, {required String meta, String? savedPath, String? name}) {
    job.status = JobStatus.completed;
    job.progress = 1;
    job.subtitle = 'Completed';
    job.savedPath = savedPath;
    addActivity(job.kind, name ?? job.title, meta, savedPath: savedPath);
    notifyListeners();
  }

  void failJob(DownloadJob job, String error) {
    job.status = JobStatus.failed;
    job.error = error;
    job.subtitle = error;
    notifyListeners();
  }

  void removeJob(DownloadJob job) {
    jobs.remove(job);
    notifyListeners();
  }

  List<DownloadJob> jobsFor(ToolKind kind) => jobs.where((j) => j.kind == kind).toList();
}
