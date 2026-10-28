import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/file_saver.dart';
import '../../services/pdf_service.dart';
import '../../services/store.dart';
import '../../util.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/scaffold.dart';

class TextToPdfScreen extends StatefulWidget {
  const TextToPdfScreen({super.key});
  @override
  State<TextToPdfScreen> createState() => _TextToPdfScreenState();
}

class _TextToPdfScreenState extends State<TextToPdfScreen> {
  final _titleCtl = TextEditingController();
  final _bodyCtl = TextEditingController();
  bool _busy = false;
  SavedFile? _saved;
  int _size = 0;

  @override
  void dispose() {
    _titleCtl.dispose();
    _bodyCtl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final body = _bodyCtl.text;
    if (body.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _saved = null;
    });
    try {
      final title = _titleCtl.text.trim();
      final bytes = await PdfService.instance.textToPdf(body, title: title.isEmpty ? 'Document' : title);
      final base = title.isEmpty ? 'document' : title;
      final fileName = '${safeName(base)}.pdf';
      final saved = await FileSaver.instance.saveDocument(bytes, fileName);
      if (!mounted) return;
      context.read<AppStore>().addActivity(
            ToolKind.docs,
            fileName,
            'Text to PDF • ${humanSize(bytes.length)}',
            savedPath: saved.path,
          );
      setState(() {
        _saved = saved;
        _size = bytes.length;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not create PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Text to PDF',
      subtitle: 'Notes → a clean PDF',
      bottomBar: PrimaryButton(
        label: 'Create PDF',
        icon: Icons.picture_as_pdf_rounded,
        busy: _busy,
        onPressed: _create,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Title (optional)'),
          TextField(
            controller: _titleCtl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'e.g. Meeting notes'),
          ),
          const SizedBox(height: 18),
          const SectionHeader('Content'),
          TextField(
            controller: _bodyCtl,
            minLines: 8,
            maxLines: 16,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Type or paste your text here…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          const InfoBanner(
            message:
                'Your text is laid out on A4 pages with page numbers. Blank lines become spacing.',
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
