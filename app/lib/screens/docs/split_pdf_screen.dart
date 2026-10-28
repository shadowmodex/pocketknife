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

class SplitPdfScreen extends StatefulWidget {
  const SplitPdfScreen({super.key});
  @override
  State<SplitPdfScreen> createState() => _SplitPdfScreenState();
}

class _SplitPdfScreenState extends State<SplitPdfScreen> {
  Uint8List? _input;
  String _name = '';
  int _pages = 0;
  final _rangeCtl = TextEditingController();
  bool _busy = false;
  SavedFile? _saved;
  int _size = 0;

  @override
  void dispose() {
    _rangeCtl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes ?? await File(f.path!).readAsBytes();
    int count = 0;
    try {
      count = PdfService.instance.pageCount(bytes);
    } catch (_) {}
    setState(() {
      _input = bytes;
      _name = f.name;
      _pages = count;
      _rangeCtl.text = count > 0 ? '1-$count' : '';
      _saved = null;
    });
  }
  // SPLIT_ACTION
  Future<void> _extract() async {
    final input = _input;
    if (input == null) return;
    final pages = parseRanges(_rangeCtl.text, _pages);
    if (pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter valid pages, e.g. 1-3, 5')));
      return;
    }
    setState(() {
      _busy = true;
      _saved = null;
    });
    try {
      final bytes = await PdfService.instance.extractPages(input, pages);
      final base = _name.contains('.') ? _name.substring(0, _name.lastIndexOf('.')) : _name;
      final fileName = '${safeName(base)}_extract.pdf';
      final saved = await FileSaver.instance.saveDocument(bytes, fileName);
      if (!mounted) return;
      context.read<AppStore>().addActivity(
            ToolKind.splitPdf,
            fileName,
            '${pages.length} pages • ${humanSize(bytes.length)}',
            savedPath: saved.path,
          );
      setState(() {
        _saved = saved;
        _size = bytes.length;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not extract: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _input == null ? 0 : parseRanges(_rangeCtl.text, _pages).length;
    return AppScaffold(
      title: 'Split / extract',
      subtitle: 'Pull pages into a new PDF',
      bottomBar: _input == null
          ? null
          : PrimaryButton(
              label: selected > 0 ? 'Extract $selected pages' : 'Extract pages',
              icon: Icons.call_split_rounded,
              busy: _busy,
              onPressed: _extract,
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_input == null)
            PickTile(
              icon: Icons.call_split_rounded,
              title: 'Choose a PDF',
              subtitle: 'Select the file to split',
              onTap: _pick,
            )
          else ...[
            PkCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  IconTile(
                      icon: Icons.picture_as_pdf_rounded,
                      color: AppColors.toolDocs,
                      bg: AppColors.toolDocsBg,
                      size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text('$_pages pages', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  GhostButton(label: 'Change', icon: Icons.swap_horiz_rounded, onPressed: _pick),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader('Pages to extract'),
            TextField(
              controller: _rangeCtl,
              keyboardType: TextInputType.text,
              onChanged: (_) => setState(() => _saved = null),
              decoration: const InputDecoration(
                hintText: 'e.g. 1-3, 5, 8-10',
                prefixIcon: Icon(Icons.tag_rounded, color: AppColors.faint, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            InfoBanner(
              message: selected > 0
                  ? '$selected of $_pages pages will be extracted, in the order listed.'
                  : 'Type page numbers or ranges. Use commas to combine, e.g. 1-3, 5.',
              icon: selected > 0 ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
              tint: selected > 0 ? AppColors.success : null,
            ),
          ],
          if (_saved != null) ...[
            const SizedBox(height: 18),
            SavedResultCard(
              title: 'Extract ready',
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
