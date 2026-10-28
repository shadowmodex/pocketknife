import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/docx_service.dart';
import '../../services/file_saver.dart';
import '../../services/store.dart';
import '../../theme/app_colors.dart';
import '../../util.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/scaffold.dart';

class WordToPdfScreen extends StatefulWidget {
  const WordToPdfScreen({super.key});
  @override
  State<WordToPdfScreen> createState() => _WordToPdfScreenState();
}

class _WordToPdfScreenState extends State<WordToPdfScreen> {
  Uint8List? _input;
  String _name = '';
  int _osize = 0;
  bool _busy = false;
  SavedFile? _saved;
  int _size = 0;

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['docx'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes ?? await File(f.path!).readAsBytes();
    setState(() {
      _input = bytes;
      _name = f.name;
      _osize = bytes.length;
      _saved = null;
    });
  }

  Future<void> _convert() async {
    if (_input == null) return;
    setState(() {
      _busy = true;
      _saved = null;
    });
    try {
      final base = _name.contains('.') ? _name.substring(0, _name.lastIndexOf('.')) : _name;
      final bytes = await DocxService.instance.docxToPdf(_input!, title: base);
      final fileName = '${safeName(base)}.pdf';
      final saved = await FileSaver.instance.saveDocument(bytes, fileName);
      if (!mounted) return;
      context.read<AppStore>().addActivity(
            ToolKind.wordToPdf,
            fileName,
            'Word to PDF • ${humanSize(bytes.length)}',
            savedPath: saved.path,
          );
      setState(() {
        _saved = saved;
        _size = bytes.length;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not convert: $e'.replaceAll('FormatException: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Word to PDF',
      subtitle: 'Convert a .docx file',
      bottomBar: _input == null
          ? null
          : PrimaryButton(
              label: 'Convert to PDF',
              icon: Icons.picture_as_pdf_rounded,
              busy: _busy,
              onPressed: _convert,
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_input == null)
            PickTile(
              icon: Icons.description_rounded,
              title: 'Choose a Word file',
              subtitle: 'Microsoft Word (.docx)',
              onTap: _pick,
            )
          else
            PkCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  IconTile(
                      icon: Icons.description_rounded,
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
                        Text(humanSize(_osize),
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  GhostButton(label: 'Change', icon: Icons.swap_horiz_rounded, onPressed: _pick),
                ],
              ),
            ),
          const SizedBox(height: 12),
          const InfoBanner(
            message:
                'Text and headings are converted. Complex layouts, images and tables may be simplified to plain text.',
          ),
          if (_saved != null) ...[
            const SizedBox(height: 18),
            SavedResultCard(
              title: 'PDF ready',
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
