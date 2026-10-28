/// Small formatting helpers shared across screens.
library;


String timeAgo(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final weeks = diff.inDays ~/ 7;
  if (weeks < 5) return '${weeks}w ago';
  final months = diff.inDays ~/ 30;
  if (months < 12) return '${months}mo ago';
  return '${diff.inDays ~/ 365}y ago';
}

/// Strip characters that are unsafe in a file name, collapse whitespace, and
/// cap the length. Falls back to "document" when nothing usable is left.
String safeName(String input) {
  var s = input.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.length > 60) s = s.substring(0, 60).trim();
  return s.isEmpty ? 'document' : s;
}

String humanSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var b = bytes.toDouble();
  var i = 0;
  while (b >= 1024 && i < units.length - 1) {
    b /= 1024;
    i++;
  }
  return '${b.toStringAsFixed(b >= 10 || i == 0 ? 0 : 1)} ${units[i]}';
}
