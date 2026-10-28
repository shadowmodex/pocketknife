import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/file_saver.dart';
import '../../theme/app_colors.dart';
import '../../util.dart';
import '../../widgets/cards.dart';
import '../../widgets/scaffold.dart';

class FilesTab extends StatefulWidget {
  const FilesTab({super.key});

  @override
  State<FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<FilesTab> {
  List<File> _files = [];
  bool _loading = true;
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final files = await FileSaver.instance.listSavedFiles();
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  Future<void> _delete(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete file?'),
        content: Text('Delete "${file.path.split(Platform.pathSeparator).last}" from storage?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FileSaver.instance.deleteFile(file.path);
      _load();
    }
  }

  void _showFileActions(File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded, color: AppColors.primary),
              title: const Text('Open with app'),
              onTap: () {
                Navigator.pop(ctx);
                FileSaver.instance.open(file.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_rounded, color: AppColors.ink),
              title: const Text('Share file'),
              onTap: () {
                Navigator.pop(ctx);
                FileSaver.instance.share(file.path, text: name);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
              title: const Text('Delete', style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(file);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp') || lower.endsWith('.gif')) {
      return Icons.image_rounded;
    }
    if (lower.endsWith('.docx') || lower.endsWith('.doc')) return Icons.description_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _colorFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return AppColors.toolMergePdf;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp') || lower.endsWith('.gif')) {
      return AppColors.toolImage;
    }
    if (lower.endsWith('.docx') || lower.endsWith('.doc')) return AppColors.toolWord;
    return AppColors.primary;
  }

  Color _bgFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return AppColors.toolMergePdfBg;
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp') || lower.endsWith('.gif')) {
      return AppColors.toolImageBg;
    }
    if (lower.endsWith('.docx') || lower.endsWith('.doc')) return AppColors.toolWordBg;
    return AppColors.accentSoft;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _files.where((f) {
      if (_search.isEmpty) return true;
      final name = f.path.split(Platform.pathSeparator).last.toLowerCase();
      return name.contains(_search.toLowerCase());
    }).toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Files', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 2),
                      Text(
                        '${_files.length} saved ${_files.length == 1 ? "file" : "files"}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                CircleIconButton(
                  icon: Icons.refresh_rounded,
                  size: 38,
                  onTap: _load,
                ),
              ],
            ),
          ),
          if (_files.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search files…',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.faint, size: 20),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _search = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
                        children: const [
                          EmptyState(
                            icon: Icons.folder_open_rounded,
                            title: 'No saved files yet',
                            message: 'Files you convert, merge, or generate will be stored here.',
                          ),
                        ],
                      )
                    : filtered.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
                            children: [
                              EmptyState(
                                icon: Icons.search_off_rounded,
                                title: 'No matching files',
                                message: 'No file matching "$_search" was found.',
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                            physics: const BouncingScrollPhysics(),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final file = filtered[i];
                              final name = file.path.split(Platform.pathSeparator).last;
                              int length = 0;
                              DateTime? modified;
                              try {
                                length = file.lengthSync();
                                modified = file.lastModifiedSync();
                              } catch (_) {}

                              return PkCard(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                onTap: () => _showFileActions(file),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: _bgFor(name),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        _iconFor(name),
                                        color: _colorFor(name),
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14.5,
                                              color: AppColors.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${humanSize(length)}${modified != null ? " • ${timeAgo(modified)}" : ""}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.more_vert_rounded, color: AppColors.faint),
                                      onPressed: () => _showFileActions(file),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

