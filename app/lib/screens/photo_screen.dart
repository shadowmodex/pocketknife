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

class _ImageItem {
  final String name;
  final Uint8List bytes;
  final int width;
  final int height;
  final int sizeBytes;

  const _ImageItem({
    required this.name,
    required this.bytes,
    required this.width,
    required this.height,
    required this.sizeBytes,
  });
}

class PhotoScreen extends StatefulWidget {
  const PhotoScreen({super.key});

  @override
  State<PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<PhotoScreen> {
  int _tabIndex = 0; // 0 = Single Image, 1 = Batch Convert

  // Single image state
  _ImageItem? _singleImage;
  // Batch images state
  final List<_ImageItem> _batchImages = [];

  // Conversion options matching Image 3
  String _selectedFormat = 'JPG'; // 'JPG', 'PNG', 'WebP', 'JPEG', 'GIF'
  int _quality = 100;
  bool _enableResize = false;
  bool _keepAspectRatio = true;
  final TextEditingController _widthCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();

  bool _busy = false;
  double _batchProgress = 0.0;
  SavedFile? _lastSaved;
  int _lastResultSize = 0;
  List<SavedFile> _batchSaved = [];

  @override
  void dispose() {
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  PicFormat get _picFormat {
    switch (_selectedFormat) {
      case 'PNG':
        return PicFormat.png;
      case 'WebP':
        return PicFormat.webp;
      case 'GIF':
        return PicFormat.gif;
      case 'JPEG':
      case 'JPG':
      default:
        return PicFormat.jpeg;
    }
  }

  Future<void> _pickSingle() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    final bytes = f.bytes ?? await File(f.path!).readAsBytes();
    final probe = PhotoService.instance.probe(bytes);
    final w = probe?.width ?? 0;
    final h = probe?.height ?? 0;

    setState(() {
      _singleImage = _ImageItem(
        name: f.name,
        bytes: bytes,
        width: w,
        height: h,
        sizeBytes: bytes.length,
      );
      _widthCtrl.text = w > 0 ? '$w' : '';
      _heightCtrl.text = h > 0 ? '$h' : '';
      _lastSaved = null;
    });
  }

  Future<void> _pickBatch() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;

    final items = <_ImageItem>[];
    for (final f in res.files) {
      final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
      if (bytes != null) {
        final probe = PhotoService.instance.probe(bytes);
        items.add(_ImageItem(
          name: f.name,
          bytes: bytes,
          width: probe?.width ?? 0,
          height: probe?.height ?? 0,
          sizeBytes: bytes.length,
        ));
      }
    }

    setState(() {
      _batchImages.addAll(items);
      _batchSaved.clear();
    });
  }

  void _onWidthChanged(String val) {
    if (!_keepAspectRatio || _singleImage == null || _singleImage!.width <= 0) return;
    final w = int.tryParse(val);
    if (w != null && w > 0) {
      final ratio = _singleImage!.height / _singleImage!.width;
      final newH = (w * ratio).round();
      _heightCtrl.text = '$newH';
    }
  }

  void _onHeightChanged(String val) {
    if (!_keepAspectRatio || _singleImage == null || _singleImage!.height <= 0) return;
    final h = int.tryParse(val);
    if (h != null && h > 0) {
      final ratio = _singleImage!.width / _singleImage!.height;
      final newW = (h * ratio).round();
      _widthCtrl.text = '$newW';
    }
  }

  Future<void> _convertSingle() async {
    if (_singleImage == null) return;
    setState(() {
      _busy = true;
      _lastSaved = null;
    });

    try {
      final reqWidth = _enableResize ? int.tryParse(_widthCtrl.text) : null;
      final reqHeight = _enableResize ? int.tryParse(_heightCtrl.text) : null;
      final resizeMode = (reqWidth != null || reqHeight != null) ? ResizeMode.exact : ResizeMode.keep;

      final opts = PhotoOptions(
        format: _picFormat,
        quality: _quality,
        resize: resizeMode,
        width: reqWidth,
        height: reqHeight,
      );

      final out = await PhotoService.instance.process(_singleImage!.bytes, opts);
      final rawName = _singleImage!.name;
      final base = rawName.contains('.') ? rawName.substring(0, rawName.lastIndexOf('.')) : rawName;
      final fileName = '${base}_pk.${_picFormat.ext}';

      final saved = await FileSaver.instance.saveImage(out.bytes, fileName);
      if (!mounted) return;

      context.read<AppStore>().addActivity(
            ToolKind.imageConverter,
            fileName,
            '${_selectedFormat.toUpperCase()} • ${out.width}×${out.height} • ${humanSize(out.sizeBytes)}',
            savedPath: saved.path,
          );

      setState(() {
        _lastSaved = saved;
        _lastResultSize = out.sizeBytes;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not convert image: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convertBatch() async {
    if (_batchImages.isEmpty) return;
    setState(() {
      _busy = true;
      _batchSaved.clear();
      _batchProgress = 0.0;
    });

    final savedList = <SavedFile>[];
    try {
      final reqWidth = _enableResize ? int.tryParse(_widthCtrl.text) : null;
      final reqHeight = _enableResize ? int.tryParse(_heightCtrl.text) : null;
      final resizeMode = (reqWidth != null || reqHeight != null) ? ResizeMode.exact : ResizeMode.keep;

      for (var i = 0; i < _batchImages.length; i++) {
        final imgItem = _batchImages[i];
        final opts = PhotoOptions(
          format: _picFormat,
          quality: _quality,
          resize: resizeMode,
          width: reqWidth,
          height: reqHeight,
        );

        final out = await PhotoService.instance.process(imgItem.bytes, opts);
        final rawName = imgItem.name;
        final base = rawName.contains('.') ? rawName.substring(0, rawName.lastIndexOf('.')) : rawName;
        final fileName = '${base}_pk.${_picFormat.ext}';

        final saved = await FileSaver.instance.saveImage(out.bytes, fileName);
        savedList.add(saved);

        if (!mounted) return;
        context.read<AppStore>().addActivity(
              ToolKind.imageConverter,
              fileName,
              '${_selectedFormat.toUpperCase()} • ${out.width}×${out.height} • ${humanSize(out.sizeBytes)}',
              savedPath: saved.path,
            );

        setState(() {
          _batchProgress = (i + 1) / _batchImages.length;
        });
      }

      setState(() {
        _batchSaved = savedList;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error in batch convert: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasInput = _tabIndex == 0 ? _singleImage != null : _batchImages.isNotEmpty;

    return AppScaffold(
      title: 'Image Converter',
      subtitle: 'Convert your images to any format',
      helpText: 'Convert single or batch images to JPG, PNG, WebP, JPEG, or GIF entirely offline. Adjust quality compression and optionally resize while maintaining aspect ratio.',
      bottomBar: hasInput
          ? PrimaryButton(
              label: _tabIndex == 0 ? 'Convert Image' : 'Convert ${_batchImages.length} Images',
              icon: Icons.sync_alt_rounded,
              busy: _busy,
              onPressed: _tabIndex == 0 ? _convertSingle : _convertBatch,
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented Tabs matching Image 3 ("Single Image" vs "Batch Convert")
          SegmentedTabs(
            tabs: const [
              (label: 'Single Image', icon: Icons.image_outlined),
              (label: 'Batch Convert', icon: Icons.photo_library_outlined),
            ],
            index: _tabIndex,
            onChanged: (i) {
              setState(() {
                _tabIndex = i;
                _lastSaved = null;
                _batchSaved.clear();
              });
            },
          ),
          const SizedBox(height: 18),

          // Tab 0: Single Image
          if (_tabIndex == 0) ...[
            if (_singleImage == null)
              PickTile(
                icon: Icons.add_photo_alternate_rounded,
                title: 'Choose an image',
                subtitle: 'JPG, PNG, WebP, GIF, or BMP',
                onTap: _pickSingle,
              )
            else
              _buildSingleImageCard(),
          ],

          // Tab 1: Batch Convert
          if (_tabIndex == 1) ...[
            if (_batchImages.isEmpty)
              PickTile(
                icon: Icons.photo_library_rounded,
                title: 'Choose images to convert',
                subtitle: 'Select multiple images for batch processing',
                onTap: _pickBatch,
              )
            else
              _buildBatchImagesList(),
          ],

          // Conversion options (Format chips, Quality slider, Resize toggle)
          if (hasInput) ...[
            const SizedBox(height: 20),
            _buildFormatSection(),
            const SizedBox(height: 20),
            _buildQualitySection(),
            const SizedBox(height: 20),
            _buildResizeSection(),
          ],

          // Progress indicator for batch
          if (_busy && _tabIndex == 1) ...[
            const SizedBox(height: 20),
            LinearProgressIndicator(value: _batchProgress, color: AppColors.primary),
            const SizedBox(height: 6),
            Text(
              'Converting ${(_batchProgress * 100).round()}%…',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],

          // Saved result card on Single completion
          if (_lastSaved != null && _tabIndex == 0) ...[
            const SizedBox(height: 20),
            SavedResultCard(
              title: 'Image converted',
              detail: '${_selectedFormat.toUpperCase()} • ${humanSize(_lastResultSize)} • ${_lastSaved!.name}',
              location: _lastSaved!.prettyLocation,
              onOpen: () => FileSaver.instance.open(_lastSaved!.path),
              onShare: () => FileSaver.instance.share(_lastSaved!.path, text: _lastSaved!.name),
            ),
          ],

          // Saved summary on Batch completion
          if (_batchSaved.isNotEmpty && _tabIndex == 1) ...[
            const SizedBox(height: 20),
            PkCard(
              color: AppColors.successBg,
              borderColor: const Color(0xFFA7F3D0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        '${_batchSaved.length} images converted successfully',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'All files converted to ${_selectedFormat.toUpperCase()} and saved in storage.',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Selected image card matching Image 3
  Widget _buildSingleImageCard() {
    final img = _singleImage!;
    final dim = img.width > 0 && img.height > 0 ? '${img.width} × ${img.height}' : '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              img.bytes,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  img.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${humanSize(img.sizeBytes)}${dim.isNotEmpty ? " • $dim" : ""}',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 12.5,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: const Color(0xFFF1F5F9),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                setState(() {
                  _singleImage = null;
                  _lastSaved = null;
                });
              },
              child: const SizedBox(
                width: 34,
                height: 34,
                child: Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchImagesList() {
    return Column(
      children: [
        SummaryBanner(
          title: '${_batchImages.length} images selected',
          subtitle: 'Ready to convert to $_selectedFormat',
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _batchImages.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final img = _batchImages[i];
            final dim = img.width > 0 && img.height > 0 ? '${img.width} × ${img.height}' : '';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(img.bytes, width: 44, height: 44, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          img.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${humanSize(img.sizeBytes)}${dim.isNotEmpty ? " • $dim" : ""}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.muted),
                    onPressed: () {
                      setState(() {
                        _batchImages.removeAt(i);
                        _batchSaved.clear();
                      });
                    },
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        SoftButton(
          label: '+ Add More Images',
          onPressed: _pickBatch,
        ),
      ],
    );
  }

  // "Convert to" chips row matching Image 3 (JPG, PNG, WebP, JPEG, GIF)
  Widget _buildFormatSection() {
    const formats = ['JPG', 'PNG', 'WebP', 'JPEG', 'GIF'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Convert to',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 10),
        FormatChips<String>(
          items: [for (final f in formats) (value: f, label: f)],
          selected: _selectedFormat,
          onChanged: (val) => setState(() => _selectedFormat = val),
        ),
      ],
    );
  }

  // Quality slider matching Image 3
  Widget _buildQualitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Quality',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            Text(
              '$_quality%',
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: const Color(0xFFE2E8F0),
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primary.withValues(alpha: 0.12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
          ),
          child: Slider(
            value: _quality.toDouble(),
            min: 10,
            max: 100,
            divisions: 90,
            onChanged: (v) => setState(() => _quality = v.round()),
          ),
        ),
      ],
    );
  }

  // "Resize (Optional)" Section matching Image 3
  Widget _buildResizeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Resize (Optional)',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            Switch(
              value: _enableResize,
              activeThumbColor: AppColors.primary,
              onChanged: (v) => setState(() => _enableResize = v),
            ),
          ],
        ),
        if (_enableResize) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Width field
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Width',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _widthCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: _onWidthChanged,
                      decoration: const InputDecoration(
                        suffixText: 'px',
                        suffixStyle: TextStyle(color: AppColors.muted, fontSize: 13),
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(10, 20, 10, 0),
                child: Icon(Icons.link_rounded, color: AppColors.muted, size: 20),
              ),
              // Height field
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Height',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.muted),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _heightCtrl,
                      keyboardType: TextInputType.number,
                      onChanged: _onHeightChanged,
                      decoration: const InputDecoration(
                        suffixText: 'px',
                        suffixStyle: TextStyle(color: AppColors.muted, fontSize: 13),
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Keep aspect ratio checkbox
          Row(
            children: [
              Checkbox(
                value: _keepAspectRatio,
                activeColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                onChanged: (v) => setState(() => _keepAspectRatio = v ?? true),
              ),
              const Text(
                'Keep aspect ratio',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
