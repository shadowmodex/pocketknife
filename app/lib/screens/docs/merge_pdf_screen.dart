import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/file_saver.dart';
import '../../services/pdf_service.dart';
import '../../services/store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../util.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/scaffold.dart';

class _PdfItem {
  final String name;
  final Uint8List bytes;
  final int pageCount;
  final Color badgeColor;

  const _PdfItem({
    required this.name,
    required this.bytes,
    required this.pageCount,
    required this.badgeColor,
  });
}

class MergePdfScreen extends StatefulWidget {
  const MergePdfScreen({super.key});

  @override
  State<MergePdfScreen> createState() => _MergePdfScreenState();
}

class _MergePdfScreenState extends State<MergePdfScreen> {
  final List<_PdfItem> _files = [];
  final TextEditingController _nameCtrl = TextEditingController(text: 'Merged_Document.pdf');
  bool _busy = false;
  SavedFile? _saved;
  int _mergedSize = 0;

  static const _badgeColors = [
    Color(0xFFEF4444), // Red
    Color(0xFF2563EB), // Blue
    Color(0xFF10B981), // Green
    Color(0xFF8B5CF6), // Purple
    Color(0xFFF59E0B), // Amber
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _addFiles() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: true,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;

    final added = <_PdfItem>[];
    for (var i = 0; i < res.files.length; i++) {
      final f = res.files[i];
      final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (bytes != null) {
        var pages = 1;
        try {
          pages = PdfService.instance.pageCount(bytes);
        } catch (_) {}
        final color = _badgeColors[(_files.length + added.length) % _badgeColors.length];
        added.add(_PdfItem(
          name: f.name,
          bytes: bytes,
          pageCount: pages,
          badgeColor: color,
        ));
      }
    }

    if (added.isEmpty) return;
    setState(() {
      _files.addAll(added);
      _saved = null;
    });
  }

  Future<void> _merge() async {
    if (_files.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 2 PDF files to merge.')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _saved = null;
    });

    try {
      final bytes = await PdfService.instance.merge([for (final f in _files) f.bytes]);
      var fileName = _nameCtrl.text.trim();
      if (fileName.isEmpty) fileName = 'Merged_Document.pdf';
      if (!fileName.toLowerCase().endsWith('.pdf')) fileName = '$fileName.pdf';

      final saved = await FileSaver.instance.saveDocument(bytes, fileName);
      if (!mounted) return;

      context.read<AppStore>().addActivity(
            ToolKind.mergePdf,
            fileName,
            'Merged ${_files.length} PDFs • ${humanSize(bytes.length)}',
            savedPath: saved.path,
          );

      setState(() {
        _saved = saved;
        _mergedSize = bytes.length;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not merge PDFs: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Merge PDF',
      subtitle: 'Combine multiple PDF files into one',
      helpText: 'Select two or more PDF files, drag to reorder them in the desired order, specify an output file name, and merge them into a single PDF document.',
      bottomBar: _files.length < 2
          ? null
          : PrimaryButton(
              label: 'Merge PDF',
              icon: Icons.call_merge_rounded,
              busy: _busy,
              onPressed: _merge,
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_files.isEmpty)
            PickTile(
              icon: Icons.picture_as_pdf_rounded,
              title: 'Add PDF files',
              subtitle: 'Pick two or more PDFs to combine',
              onTap: _addFiles,
            )
          else ...[
            // Soft pink summary banner matching Image 2
            SummaryBanner(
              title: '${_files.length} files selected',
              subtitle: 'Drag to reorder. Tap to preview.',
            ),
            const SizedBox(height: 14),

            // Reorderable list of PDF items
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: _files.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = _files.removeAt(oldIndex);
                  _files.insert(newIndex, item);
                  _saved = null;
                });
              },
              itemBuilder: (context, i) {
                final file = _files[i];
                final pageLabel = '${file.pageCount} ${file.pageCount == 1 ? "page" : "pages"}';
                return KeyedSubtree(
                  key: ValueKey('pdf_${file.name}_$i'),
                  child: PdfFileCard(
                    name: file.name,
                    details: '${humanSize(file.bytes.length)} • $pageLabel',
                    badgeColor: file.badgeColor,
                    dragHandle: ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        child: Icon(Icons.menu_rounded, color: AppColors.faint, size: 20),
                      ),
                    ),
                    onRemove: () {
                      setState(() {
                        _files.removeAt(i);
                        _saved = null;
                      });
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 4),

            // "+ Add More PDFs" Soft pill button
            SoftButton(
              label: '+ Add More PDFs',
              onPressed: _addFiles,
            ),
            const SizedBox(height: 20),

            // Output File Name input field matching Image 2
            const Text(
              'Output File Name',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: 'Merged_Document.pdf',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                  onPressed: () => _nameCtrl.clear(),
                ),
              ),
            ),
          ],

          // Saved result card on success
          if (_saved != null) ...[
            const SizedBox(height: 20),
            SavedResultCard(
              title: 'Merged PDF ready',
              detail: '${humanSize(_mergedSize)} • ${_saved!.name}',
              location: _saved!.prettyLocation,
              onOpen: () => FileSaver.instance.open(_saved!.path),
              onShare: () => FileSaver.instance.share(_saved!.path, text: _saved!.name),
            ),
          ],
        ],
      ),
    );
  }
}
