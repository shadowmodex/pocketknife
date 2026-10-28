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

class CompressPdfScreen extends StatefulWidget {
  const CompressPdfScreen({super.key});
  @override
  State<CompressPdfScreen> createState() => _CompressPdfScreenState();
}

class _CompressPdfScreenState extends State<CompressPdfScreen> {
  Uint8List? _input;
  String _name = '';
  int _osize = 0;
  int _pages = 0;
  CompressStrength _strength = CompressStrength.medium;
  bool _busy = false;
  SavedFile? _saved;
  int _size = 0;

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
      _osize = bytes.length;
      _pages = count;
      _saved = null;
    });
  }
  // COMPRESS_ACTION
  Future<void> _compress() async {
    final input = _input;
    if (input == null) return;
    setState(() {
      _busy = true;
      _saved = null;
    });
    try {
      final bytes = await PdfService.instance.compress(input, _strength);
      final base = _name.contains('.') ? _name.substring(0, _name.lastIndexOf('.')) : _name;
      final fileName = '${safeName(base)}_small.pdf';
      final saved = await FileSaver.instance.saveDocument(bytes, fileName);
      if (!mounted) return;
      context.read<AppStore>().addActivity(
            ToolKind.compressPdf,
            fileName,
            'Compressed • ${humanSize(bytes.length)}',
            savedPath: saved.path,
          );
      setState(() {
        _saved = saved;
        _size = bytes.length;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not compress: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final delta = (_saved != null && _osize > 0)
        ? (100 - (_size / _osize * 100)).round()
        : 0;
    return AppScaffold(
      title: 'Compress PDF',
      subtitle: 'Shrink a large PDF',
      bottomBar: _input == null
          ? null
          : PrimaryButton(
              label: _saved == null ? 'Compress PDF' : 'Compress again',
              icon: Icons.compress_rounded,
              busy: _busy,
              onPressed: _compress,
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_input == null)
            PickTile(
              icon: Icons.compress_rounded,
              title: 'Choose a PDF',
              subtitle: 'Select the file to shrink',
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
                        Text('$_pages pages • ${humanSize(_osize)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  GhostButton(label: 'Change', icon: Icons.swap_horiz_rounded, onPressed: _pick),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader('Compression level'),
            PkCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < CompressStrength.values.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 46),
                    OptionTile(
                      title: CompressStrength.values[i].label,
                      trailing: CompressStrength.values[i].hint,
                      selected: CompressStrength.values[i] == _strength,
                      recommended: CompressStrength.values[i] == CompressStrength.medium,
                      onTap: () => setState(() {
                        _strength = CompressStrength.values[i];
                        _saved = null;
                      }),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            const InfoBanner(
              message:
                  'Pages are re-rendered as images to shrink them, so selectable text is not preserved. Great for scans and photo-heavy PDFs.',
            ),
          ],
          if (_saved != null) ...[
            const SizedBox(height: 18),
            SavedResultCard(
              title: delta > 0 ? '$delta% smaller' : 'Compressed',
              detail: '${humanSize(_osize)} → ${humanSize(_size)}',
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
