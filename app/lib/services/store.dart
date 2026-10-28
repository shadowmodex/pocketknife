import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// App-wide state: user settings and the recent-activity log.
/// Activity and settings persist across launches.
class AppStore extends ChangeNotifier {
  AppStore(this._prefs) {
    _load();
  }

  final SharedPreferences _prefs;

  static const _kActivity = 'pk.activity';
  static const _kSaveToGallery = 'pk.saveGallery';

  // ---- settings ----
  bool saveToGallery = true;

  // ---- data ----
  final List<ActivityItem> activity = [];

  void _load() {
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
}
