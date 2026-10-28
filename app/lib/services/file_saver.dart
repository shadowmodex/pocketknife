import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';

/// Where an output ended up, so the UI can offer Open / Share and show a path.
class SavedFile {
  final String name;
  final String path; // absolute path on disk (always present, app-private if needed)
  final bool inGallery; // true when it also landed in the public gallery/Downloads
  const SavedFile({required this.name, required this.path, required this.inGallery});

  String get prettyLocation => inGallery ? 'Saved to your device' : 'Saved in app storage';
}

/// Handles persisting generated files. Images go to the gallery;
/// documents go to a public Pocketknife folder when possible, and
/// always to app storage as a reliable fallback that Share/Open can use.
class FileSaver {
  FileSaver._();
  static final FileSaver instance = FileSaver._();

  static const _albumImages = 'Pocketknife';
  static const _relDocs = 'Download/Pocketknife';

  /// A private scratch directory for intermediate work.
  Future<Directory> workDir() async {
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/pocketknife');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// A durable app-private directory guaranteed to be writable without permissions.
  Future<Directory> _appOut() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/Pocketknife');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Public accessor for the files storage directory.
  Future<Directory> getSavedFilesDir() => _appOut();

  /// Retrieve all locally saved files ordered by last modified (newest first).
  Future<List<File>> listSavedFiles() async {
    try {
      final dir = await _appOut();
      if (!await dir.exists()) return [];
      final entries = await dir.list().toList();
      final files = entries.whereType<File>().toList();
      files.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });
      return files;
    } catch (e) {
      if (kDebugMode) debugPrint('Error listing saved files: $e');
      return [];
    }
  }

  /// Delete a saved file.
  Future<bool> deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
        return true;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error deleting file: $e');
    }
    return false;
  }

  Future<void> _ensureLegacyPermission() async {
    // Android <= 9 needs WRITE_EXTERNAL_STORAGE for MediaStore; 10+ does not.
    if (!Platform.isAndroid) return;
    if (await Permission.storage.isGranted) return;
    final status = await Permission.storage.status;
    if (status.isDenied) {
      await Permission.storage.request();
    }
  }

  Future<SavedFile> saveImage(Uint8List bytes, String name) async {
    // Keep a private copy first so Open/Share always work.
    final local = await _writeLocal(bytes, name);
    var inGallery = false;
    try {
      await _ensureLegacyPermission();
      final res = await SaverGallery.saveImage(
        bytes,
        fileName: name,
        skipIfExists: false,
        androidRelativePath: 'Pictures/$_albumImages',
      );
      inGallery = res.isSuccess;
    } catch (e) {
      if (kDebugMode) debugPrint('saveImage gallery failed: $e');
    }
    return SavedFile(name: name, path: local.path, inGallery: inGallery);
  }

  /// Documents (PDF/DOCX/etc.). Tries the public Download/Pocketknife folder,
  /// always keeps an app-storage copy.
  Future<SavedFile> saveDocument(Uint8List bytes, String name) async {
    final local = await _writeLocal(bytes, name);
    var inPublic = false;
    if (Platform.isAndroid) {
      try {
        await _ensureLegacyPermission();
        final res = await SaverGallery.saveFile(
          filePath: local.path,
          fileName: name,
          skipIfExists: false,
          androidRelativePath: _relDocs,
        );
        inPublic = res.isSuccess;
      } catch (e) {
        if (kDebugMode) debugPrint('saveDocument public failed: $e');
      }
    }
    return SavedFile(name: name, path: local.path, inGallery: inPublic);
  }

  Future<File> _writeLocal(Uint8List bytes, String name) async {
    final dir = await _appOut();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  Future<void> open(String path) async {
    await OpenFilex.open(path);
  }

  Future<void> share(String path, {String? text}) async {
    await Share.shareXFiles([XFile(path)], text: text);
  }
}
