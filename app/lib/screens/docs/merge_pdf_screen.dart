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
import '../../util.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/scaffold.dart';

class _Pdf {
  final String name;
  final Uint8List bytes;
  const _Pdf(this.name, this.bytes);
}

class MergePdfScreen extends StatefulWidget {
  const MergePdfScreen({super.key});
  @override
  State<MergePdfScreen> createState() => _MergePdfScreenState();
}

class _MergePdfScreenState extends State<MergePdfScreen> {
  final List<_Pdf> _files = [];
  bool _busy = false;
  SavedFile? _saved;
  int _size = 0;

  Future<void> _add() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: true,
      withData: true,
    );
    if (res == null) return;
    final added = <_Pdf>[];
    for (final f in res.files) {
      final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (bytes != null) added.add(_Pdf(f.name, bytes));
    }
    if (added.isEmpty) return;
    setState(() {
      _files.addAll(added);
      _saved = null;
    });
  }
  // MERGE_ACTION
  Future<void> _merge() async {
    if (_files.length < 2) return;
    setState(() {
      _busy = true;
      _saved = null;
    });
    try {
      final bytes = await PdfService.instance.merge([for (final f in _files) f.bytes]);
      final fileName = 'merged_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final saved = await FileSaver.instance.saveDocument(bytes, fileName);
      if (!mounted) return;
      context.read<AppStore>().addActivity(
            ToolKind.docs,
            fileName,
            'Merged ${_files.length} PDFs • ${humanSize(bytes.length)}',
            savedPath: saved.path,
          );
      setState(() {
        _saved = saved;
        _size = bytes.length;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not merge: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Merge PDFs',
      subtitle: 'Combine into one file',
      bottomBar: _files.length < 2
          ? null
          : PrimaryButton(
              label: 'Merge ${_files.length} PDFs',
              icon: Icons.merge_rounded,
              busy: _busy,
              onPressed: _merge,
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_files.isEmpty)
            PickTile(
              icon: Icons.merge_rounded,
              title: 'Add PDF files',
              subtitle: 'Pick two or more PDFs',
              onTap: _add,
            )
          else ...[
            const SectionHeader('Files in order'),
            PkCard(
              padding: EdgeInsets.zero,
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _files.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _files.removeAt(oldIndex);
                    _files.insert(newIndex, item);
                    _saved = null;
                  });
                },
                itemBuilder: (context, i) {
                  return Padding(
                    key: ValueKey('pdf_$i${_files[i].name}'),
                    padding: EdgeInsets.only(top: i == 0 ? 4 : 0, bottom: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Text('${i + 1}',
                            style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(width: 8),
                        IconTile(
                            icon: Icons.picture_as_pdf_rounded,
                            color: AppColors.toolDocs,
                            bg: AppColors.toolDocsBg,
                            size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_files[i].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall),
                              Text(humanSize(_files[i].bytes.length),
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() {
                            _files.removeAt(i);
                            _saved = null;
                          }),
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.faint),
                          visualDensity: VisualDensity.compact,
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: const Padding(
                            padding: EdgeInsets.only(right: 8, left: 2),
                            child: Icon(Icons.drag_handle_rounded, color: AppColors.faint),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            GhostButton(label: 'Add more', icon: Icons.add_rounded, onPressed: _add),
            const SizedBox(height: 10),
            const InfoBanner(message: 'Drag the handle to reorder. Files merge top to bottom.'),
          ],
          if (_saved != null) ...[
            const SizedBox(height: 18),
            SavedResultCard(
              title: 'Merged PDF ready',
              detail: '${humanSize(_size)} • ${_saved!.name}',
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
