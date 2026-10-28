import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/file_saver.dart';
import '../services/photo_service.dart';
import '../services/store.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../util.dart';
import '../widgets/cards.dart';
import '../widgets/controls.dart';
import '../widgets/scaffold.dart';

class PhotoScreen extends StatefulWidget {
  const PhotoScreen({super.key});
  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> {
  Uint8List? _input;
  String _name = 'image';
  int _ow = 0, _oh = 0, _osize = 0;

  PicFormat _format = PicFormat.jpeg;
  int _quality = 90;
  ResizeMode _resize = ResizeMode.keep;
  int _maxDim = 1920;
  final _wCtl = TextEditingController();
  final _hCtl = TextEditingController();
  bool _useTarget = false;
  double _targetKb = 500;

  bool _busy = false;
  ProcessedImage? _result;
  SavedFile? _saved;

  @override
  void dispose() {
    _wCtl.dispose();
    _hCtl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes ?? await File(f.path!).readAsBytes();
    final probe = PhotoService.instance.probe(bytes);
    setState(() {
      _input = bytes;
      _name = f.name;
      _osize = bytes.length;
      _ow = probe?.width ?? 0;
      _oh = probe?.height ?? 0;
      _wCtl.text = _ow > 0 ? '$_ow' : '';
      _hCtl.text = _oh > 0 ? '$_oh' : '';
      _result = null;
      _saved = null;
    });
  }

  Future<void> _process() async {
    if (_input == null) return;
    setState(() {
      _busy = true;
      _result = null;
      _saved = null;
    });
    try {
      final opts = PhotoOptions(
        format: _format,
        quality: _quality,
        resize: _resize,
        maxDimension: _maxDim,
        width: int.tryParse(_wCtl.text),
        height: int.tryParse(_hCtl.text),
        targetKb: _useTarget ? _targetKb.round() : null,
      );
      final out = await PhotoService.instance.process(_input!, opts);
      final base = _name.contains('.') ? _name.substring(0, _name.lastIndexOf('.')) : _name;
      final fileName = '${base}_pk.${_format.ext}';
      final saved = await FileSaver.instance.saveImage(out.bytes, fileName);
      if (!mounted) return;
      context.read<AppStore>().addActivity(
            ToolKind.photo,
            fileName,
            '${_format.label} • ${out.width}×${out.height} • ${humanSize(out.sizeBytes)}',
            savedPath: saved.path,
          );
      setState(() {
        _result = out;
        _saved = saved;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not process image: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Photo Resizer',
      subtitle: 'Resize, convert & shrink',
      bottomBar: _input == null
          ? null
          : PrimaryButton(
              label: _result == null ? 'Process image' : 'Process again',
              icon: Icons.auto_awesome_rounded,
              busy: _busy,
              onPressed: _process,
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_input == null) _pickTile() else _preview(),
          if (_input != null) ...[
            const SizedBox(height: 18),
            ..._options(context),
          ],
          if (_result != null) ...[
            const SizedBox(height: 18),
            _resultCard(context),
          ],
        ],
      ),
    );
  }

  Widget _pickTile() {
    return GestureDetector(
      onTap: _pick,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 46),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.lineStrong, width: 1.4),
        ),
        child: Column(
          children: [
            IconTile(
                icon: Icons.add_photo_alternate_rounded,
                color: AppColors.toolPhoto,
                bg: AppColors.toolPhotoBg,
                size: 56),
            const SizedBox(height: 14),
            Text('Choose a photo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('JPG, PNG, WEBP or BMP',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    return PkCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Image.memory(_input!,
                height: 190, width: double.infinity, fit: BoxFit.cover),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text('$_ow×$_oh • ${humanSize(_osize)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              GhostButton(label: 'Change', icon: Icons.swap_horiz_rounded, onPressed: _pick),
            ],
          ),
        ],
      ),
    );
  }
  // OPTIONS_AND_RESULT
  List<Widget> _options(BuildContext context) {
    return [
      const SectionHeader('Format'),
      ChoiceChips<PicFormat>(
        items: const [
          (value: PicFormat.jpeg, label: 'JPG'),
          (value: PicFormat.png, label: 'PNG'),
          (value: PicFormat.webp, label: 'WEBP'),
          (value: PicFormat.bmp, label: 'BMP'),
        ],
        selected: _format,
        onChanged: (v) => setState(() => _format = v),
      ),
      const SizedBox(height: 18),
      const SectionHeader('Resize'),
      SegmentedTabs(
        tabs: const ['Keep', 'Max size', 'Exact'],
        index: _resize.index,
        onChanged: (i) => setState(() => _resize = ResizeMode.values[i]),
      ),
      if (_resize == ResizeMode.maxDimension) ...[
        const SizedBox(height: 12),
        ChoiceChips<int>(
          items: const [
            (value: 2560, label: '2560'),
            (value: 1920, label: '1920'),
            (value: 1280, label: '1280'),
            (value: 720, label: '720'),
          ],
          selected: _maxDim,
          onChanged: (v) => setState(() => _maxDim = v),
        ),
        const SizedBox(height: 8),
        Text('Longest side in pixels — aspect ratio is kept.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
      if (_resize == ResizeMode.exact) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _numField(_wCtl, 'Width')),
          const SizedBox(width: 12),
          Expanded(child: _numField(_hCtl, 'Height')),
        ]),
      ],
      if (_format.isLossy) ...[
        const SizedBox(height: 18),
        const SectionHeader('Compression'),
        _compressionCard(context),
      ],
    ];
  }

  Widget _numField(TextEditingController c, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: label),
        ),
      ],
    );
  }
  // RESULT_CARD
  Widget _compressionCard(BuildContext context) {
    return PkCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Target file size', style: Theme.of(context).textTheme.titleSmall),
                    Text('Auto-tune quality to hit a size',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Switch(
                value: _useTarget,
                activeColor: AppColors.accent,
                onChanged: (v) => setState(() => _useTarget = v),
              ),
            ],
          ),
          if (_useTarget) ...[
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _targetKb,
                    min: 50,
                    max: 5000,
                    divisions: 99,
                    label: '${_targetKb.round()} KB',
                    onChanged: (v) => setState(() => _targetKb = v),
                  ),
                ),
                SizedBox(
                  width: 74,
                  child: Text('${_targetKb.round()} KB',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _quality.toDouble(),
                    min: 40,
                    max: 100,
                    divisions: 60,
                    label: '$_quality',
                    onChanged: (v) => setState(() => _quality = v.round()),
                  ),
                ),
                SizedBox(
                  width: 74,
                  child: Text('Quality $_quality',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultCard(BuildContext context) {
    final r = _result!;
    final saved = _saved!;
    final delta = _osize > 0 ? (100 - (r.sizeBytes / _osize * 100)).round() : 0;
    return PkCard(
      color: AppColors.successBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
              const SizedBox(width: 8),
              Text('Done', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (delta > 0)
                Text('$delta% smaller',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: AppColors.success)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${r.format.label} • ${r.width}×${r.height} • ${humanSize(r.sizeBytes)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.ink),
          ),
          Text(saved.prettyLocation, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: 'Open',
                  icon: Icons.open_in_new_rounded,
                  expand: true,
                  onPressed: () => FileSaver.instance.open(saved.path),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GhostButton(
                  label: 'Share',
                  icon: Icons.ios_share_rounded,
                  expand: true,
                  onPressed: () => FileSaver.instance.share(saved.path, text: saved.name),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

