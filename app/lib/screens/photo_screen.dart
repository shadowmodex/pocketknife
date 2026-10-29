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

  // Conversion options
  String _selectedFormat = 'JPG'; // 'JPG', 'PNG', 'WebP', 'JPEG', 'GIF'
  int _quality = 95;

  // Target File Size & Compression Mode state
  bool _enableTargetSize = false;
  CompressionMode _compressionMode = CompressionMode.highQuality;
  final TextEditingController _targetSizeCtrl = TextEditingController(text: '500');
  String _targetUnit = 'KB'; // 'KB' or 'MB'

  // Exact Pixel Resize state (NO percentage slider)
  bool _enableResize = false;
  bool _keepAspectRatio = true;
  final TextEditingController _widthCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();

  // Results & Before/After preview state
  bool _busy = false;
  double _batchProgress = 0.0;
  SavedFile? _lastSaved;
  ProcessedImage? _lastProcessed;
  int _previewModeIndex = 2; // 0 = Before, 1 = After, 2 = Side-by-Side
  final List<SavedFile> _batchSaved = [];
  final List<ProcessedImage> _batchProcessed = [];

  @override
  void dispose() {
    _targetSizeCtrl.dispose();
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

  int? get _targetSizeBytes {
    if (!_enableTargetSize) return null;
    final text = _targetSizeCtrl.text.trim();
    final value = double.tryParse(text);
    if (value == null || value <= 0) return null;
    if (_targetUnit == 'MB') {
      return (value * 1024 * 1024).round();
    }
    return (value * 1024).round();
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
      _lastProcessed = null;
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
      _batchProcessed.clear();
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

  void _applyTargetPreset(double value, String unit) {
    setState(() {
      _enableTargetSize = true;
      _targetUnit = unit;
      _targetSizeCtrl.text = value == value.roundToDouble() ? '${value.toInt()}' : '$value';
    });
  }

  Future<void> _convertSingle() async {
    if (_singleImage == null) return;
    setState(() {
      _busy = true;
      _lastSaved = null;
      _lastProcessed = null;
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
        targetSizeBytes: _targetSizeBytes,
        mode: _compressionMode,
      );

      final out = await PhotoService.instance.process(_singleImage!.bytes, opts);
      final rawName = _singleImage!.name;
      final base = rawName.contains('.') ? rawName.substring(0, rawName.lastIndexOf('.')) : rawName;
      final fileName = '${base}_pk.${_picFormat.ext}';

      final saved = await FileSaver.instance.saveImage(out.bytes, fileName);
      if (!mounted) return;

      final targetStr = _targetSizeBytes != null ? ' • Target: ${humanSize(_targetSizeBytes!)}' : '';
      context.read<AppStore>().addActivity(
            ToolKind.imageConverter,
            fileName,
            '${_selectedFormat.toUpperCase()} • ${out.width}×${out.height} • ${humanSize(out.sizeBytes)}$targetStr • ${_compressionMode.label}',
            savedPath: saved.path,
          );

      setState(() {
        _lastSaved = saved;
        _lastProcessed = out;
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
      _batchProcessed.clear();
      _batchProgress = 0.0;
    });

    final savedList = <SavedFile>[];
    final processedList = <ProcessedImage>[];
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
          targetSizeBytes: _targetSizeBytes,
          mode: _compressionMode,
        );

        final out = await PhotoService.instance.process(imgItem.bytes, opts);
        final rawName = imgItem.name;
        final base = rawName.contains('.') ? rawName.substring(0, rawName.lastIndexOf('.')) : rawName;
        final fileName = '${base}_pk.${_picFormat.ext}';

        final saved = await FileSaver.instance.saveImage(out.bytes, fileName);
        savedList.add(saved);
        processedList.add(out);

        if (!mounted) return;
        final targetStr = _targetSizeBytes != null ? ' • Target: ${humanSize(_targetSizeBytes!)}' : '';
        context.read<AppStore>().addActivity(
              ToolKind.imageConverter,
              fileName,
              '${_selectedFormat.toUpperCase()} • ${out.width}×${out.height} • ${humanSize(out.sizeBytes)}$targetStr',
              savedPath: saved.path,
            );

        setState(() {
          _batchProgress = (i + 1) / _batchImages.length;
        });
      }

      setState(() {
        _batchSaved.addAll(savedList);
        _batchProcessed.addAll(processedList);
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
      subtitle: 'Convert and optimize your images offline',
      helpText: 'Convert single or batch images to JPG, PNG, WebP, JPEG, or GIF. Choose quality-first compression modes, specify target file sizes, or set exact pixel dimensions without degradation.',
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
          // Segmented Tabs ("Single Image" vs "Batch Convert")
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
                _lastProcessed = null;
                _batchSaved.clear();
                _batchProcessed.clear();
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

          // Conversion options
          if (hasInput) ...[
            const SizedBox(height: 20),
            _buildFormatSection(),
            const SizedBox(height: 20),
            _buildTargetSizeSection(),
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
          if (_lastSaved != null && _lastProcessed != null && _tabIndex == 0) ...[
            const SizedBox(height: 20),
            _buildSingleResultCard(),
          ],

          // Saved summary on Batch completion
          if (_batchSaved.isNotEmpty && _tabIndex == 1) ...[
            const SizedBox(height: 20),
            _buildBatchResultCard(),
          ],
        ],
      ),
    );
  }

  // Selected image card
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
                  _lastProcessed = null;
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
                        _batchProcessed.clear();
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

  // Format selection chips (JPG, PNG, WebP, JPEG, GIF)
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

  // Target File Size section with 3 Compression Modes, KB/MB selector, and presets
  Widget _buildTargetSizeSection() {
    const presets = [
      (label: '100 KB', value: 100.0, unit: 'KB'),
      (label: '200 KB', value: 200.0, unit: 'KB'),
      (label: '500 KB', value: 500.0, unit: 'KB'),
      (label: '1 MB', value: 1.0, unit: 'MB'),
      (label: '2 MB', value: 2.0, unit: 'MB'),
      (label: '5 MB', value: 5.0, unit: 'MB'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Target File Size',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                Text(
                  _enableTargetSize
                      ? 'Quality-first optimization with ${_compressionMode.label}'
                      : 'Disabled (normal conversion)',
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
            Switch(
              value: _enableTargetSize,
              activeThumbColor: AppColors.primary,
              onChanged: (v) {
                setState(() {
                  _enableTargetSize = v;
                  // High Quality is the default whenever Target File Size is enabled
                  if (v) _compressionMode = CompressionMode.highQuality;
                });
              },
            ),
          ],
        ),
        if (_enableTargetSize) ...[
          const SizedBox(height: 14),

          // 1. Compression Mode Cards (High Quality, Balanced, Smallest Size)
          const Text(
            'Compression Mode',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildModeCard(
                  mode: CompressionMode.highQuality,
                  title: 'High Quality',
                  subtitle: 'Min Q: 85 • No resize',
                  icon: Icons.verified_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeCard(
                  mode: CompressionMode.balanced,
                  title: 'Balanced',
                  subtitle: 'Min Q: 65 • Limited',
                  icon: Icons.balance_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeCard(
                  mode: CompressionMode.smallestSize,
                  title: 'Smallest Size',
                  subtitle: 'Min Q: 30 • Aggressive',
                  icon: Icons.compress_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _compressionMode.description,
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.3),
          ),
          if (_compressionMode == CompressionMode.smallestSize) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB45309)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Smallest Size prioritizes small bytes. May produce noticeable compression artifacts or blur.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF92400E), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // 2. Input field and unit toggle
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _targetSizeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Desired File Size',
                    hintText: 'e.g. 500',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // KB / MB Toggle
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    _buildUnitButton('KB'),
                    _buildUnitButton('MB'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. Presets row
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in presets)
                InkWell(
                  onTap: () => _applyTargetPreset(p.value, p.unit),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_targetUnit == p.unit && _targetSizeCtrl.text == (p.value == p.value.roundToDouble() ? '${p.value.toInt()}' : '${p.value}'))
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (_targetUnit == p.unit && _targetSizeCtrl.text == (p.value == p.value.roundToDouble() ? '${p.value.toInt()}' : '${p.value}'))
                            ? AppColors.primary
                            : AppColors.line,
                      ),
                    ),
                    child: Text(
                      p.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: (_targetUnit == p.unit && _targetSizeCtrl.text == (p.value == p.value.roundToDouble() ? '${p.value.toInt()}' : '${p.value}'))
                            ? AppColors.primary
                            : AppColors.ink,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 4. Format-specific explanation
          _buildFormatNotice(),
        ],
      ],
    );
  }

  Widget _buildModeCard({
    required CompressionMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _compressionMode == mode;
    return InkWell(
      onTap: () => setState(() => _compressionMode = mode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.line,
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppColors.primary : AppColors.muted,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? AppColors.primary : AppColors.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? AppColors.primary : AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitButton(String unit) {
    final isSelected = _targetUnit == unit;
    return InkWell(
      onTap: () => setState(() => _targetUnit = unit),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          unit,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }

  Widget _buildFormatNotice() {
    String msg;
    if (_selectedFormat == 'PNG') {
      msg = _compressionMode == CompressionMode.highQuality
          ? 'PNG is a lossless format and cannot reduce bytes without downscaling. High Quality mode strictly preserves original dimensions.'
          : 'PNG uses lossless compression. PocketKnife uses limited dimension downscaling in ${_compressionMode.label} mode to approach your target size.';
    } else if (_selectedFormat == 'GIF') {
      msg = 'GIF uses indexed colors. PocketKnife preserves all animation frames and transparency when present.';
    } else {
      msg = _compressionMode == CompressionMode.highQuality
          ? 'Quality is optimized between 85% and $_quality% ceiling. High Quality never automatically downscales dimensions.'
          : 'Quality is optimized above ${_compressionMode.qualityFloor}%. Limited dimension downscaling is applied only if quality reduction alone cannot fit.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(fontSize: 11.5, height: 1.35, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  // Quality slider with mode interaction explanation
  Widget _buildQualitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  _enableTargetSize
                      ? 'Starting quality ceiling (Mode floor: ${_compressionMode.qualityFloor}%)'
                      : 'Fixed encoding quality',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ],
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

  // Exact Pixel Resize Section (NO percentage slider)
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

  // Detailed measured results card on Single completion with Before-and-After preview
  Widget _buildSingleResultCard() {
    final proc = _lastProcessed!;
    final saved = _lastSaved!;
    final isTargetSet = proc.targetSizeBytes != null && proc.targetSizeBytes! > 0;
    final success = proc.targetAchieved;
    final reduction = proc.reductionPercentage;

    return PkCard(
      color: success ? AppColors.successBg : const Color(0xFFFFFBEB),
      borderColor: success ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                success ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: success ? AppColors.success : const Color(0xFFD97706),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  success
                      ? (isTargetSet ? 'Target File Size Achieved' : 'Image Converted Successfully')
                      : 'Quality Floor Preserved',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (isTargetSet)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: success ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    success ? 'TARGET MET' : 'FLOOR PRESERVED',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: success ? const Color(0xFF065F46) : const Color(0xFF92400E),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            proc.statusMessage,
            style: TextStyle(
              fontSize: 12.5,
              color: success ? const Color(0xFF047857) : const Color(0xFFB45309),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (proc.warningMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, size: 16, color: Color(0xFFB45309)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      proc.warningMessage!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Metrics box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: success ? const Color(0xFFD1FAE5) : const Color(0xFFFDE68A),
              ),
            ),
            child: Column(
              children: [
                _buildMetricRow('Original Size', humanSize(proc.originalSizeBytes)),
                if (isTargetSet)
                  _buildMetricRow('Target Size', humanSize(proc.targetSizeBytes!)),
                _buildMetricRow(
                  'Final Size',
                  humanSize(proc.sizeBytes),
                  isHighlight: true,
                ),
                if (isTargetSet)
                  _buildMetricRow('Compression Mode', proc.mode.label),
                if (proc.achievedQuality != null)
                  _buildMetricRow('Achieved Quality', '${proc.achievedQuality}%'),
                if (reduction > 0)
                  _buildMetricRow(
                    'Size Reduction',
                    '-${reduction.toStringAsFixed(1)}%',
                    valueColor: AppColors.success,
                  ),
                _buildMetricRow(
                  'Dimensions',
                  proc.dimensionsChanged
                      ? '${proc.originalWidth}×${proc.originalHeight} → ${proc.width}×${proc.height}'
                      : '${proc.width} × ${proc.height} (100% preserved)',
                ),
              ],
            ),
          ),

          // Visual Before-and-After Inspection Widget
          _buildBeforeAfterPreview(),

          const SizedBox(height: 10),
          Text(saved.prettyLocation, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => FileSaver.instance.open(saved.path),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.lineStrong),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => FileSaver.instance.share(saved.path, text: saved.name),
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: const Text('Share'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    side: const BorderSide(color: AppColors.lineStrong),
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Interactive Before / After Visual Comparison
  Widget _buildBeforeAfterPreview() {
    final orig = _singleImage!;
    final proc = _lastProcessed!;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.compare_rounded, size: 18, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text(
                    'Visual Quality Comparison',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink),
                  ),
                ],
              ),
              // View toggle buttons: Side-by-Side vs Before vs After
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Before', style: TextStyle(fontSize: 10.5))),
                  ButtonSegment(value: 1, label: Text('After', style: TextStyle(fontSize: 10.5))),
                  ButtonSegment(value: 2, label: Text('Both', style: TextStyle(fontSize: 10.5))),
                ],
                selected: {_previewModeIndex},
                onSelectionChanged: (set) => setState(() => _previewModeIndex = set.first),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (_previewModeIndex == 2)
            // Side-by-Side
            Row(
              children: [
                Expanded(
                  child: _buildImageComparePane(
                    title: 'Original (Before)',
                    bytes: orig.bytes,
                    sizeText: humanSize(orig.sizeBytes),
                    dimText: '${proc.originalWidth} × ${proc.originalHeight}',
                    badgeColor: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildImageComparePane(
                    title: 'Converted (After)',
                    bytes: proc.bytes,
                    sizeText: humanSize(proc.sizeBytes),
                    dimText: '${proc.width} × ${proc.height}',
                    badgeColor: proc.targetAchieved ? AppColors.success : const Color(0xFFD97706),
                  ),
                ),
              ],
            )
          else if (_previewModeIndex == 0)
            // Single Before pane
            _buildImageComparePane(
              title: 'Original (Before)',
              bytes: orig.bytes,
              sizeText: humanSize(orig.sizeBytes),
              dimText: '${proc.originalWidth} × ${proc.originalHeight}',
              badgeColor: const Color(0xFF64748B),
              height: 160,
            )
          else
            // Single After pane
            _buildImageComparePane(
              title: 'Converted (After • ${proc.mode.label})',
              bytes: proc.bytes,
              sizeText: humanSize(proc.sizeBytes),
              dimText: '${proc.width} × ${proc.height}',
              badgeColor: proc.targetAchieved ? AppColors.success : const Color(0xFFD97706),
              height: 160,
            ),
        ],
      ),
    );
  }

  Widget _buildImageComparePane({
    required String title,
    required Uint8List bytes,
    required String sizeText,
    required String dimText,
    required Color badgeColor,
    double height = 110,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: badgeColor),
                  ),
                ),
                Text(
                  sizeText,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: badgeColor),
                ),
              ],
            ),
          ),
          ClipRRect(
            child: Image.memory(
              bytes,
              height: height,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              dimText,
              style: const TextStyle(fontSize: 10, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, {bool isHighlight = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  // Summary on Batch completion
  Widget _buildBatchResultCard() {
    final totalOriginal = _batchProcessed.fold<int>(0, (sum, p) => sum + p.originalSizeBytes);
    final totalFinal = _batchProcessed.fold<int>(0, (sum, p) => sum + p.sizeBytes);
    final metCount = _batchProcessed.where((p) => p.targetAchieved).length;
    final isTargetSet = _targetSizeBytes != null && _targetSizeBytes! > 0;
    final totalReduction = totalOriginal > 0 && totalOriginal > totalFinal
        ? ((totalOriginal - totalFinal) / totalOriginal * 100).toStringAsFixed(1)
        : '0';

    return PkCard(
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
            'Converted to ${_selectedFormat.toUpperCase()} (${_compressionMode.label}) • Total: ${humanSize(totalOriginal)} → ${humanSize(totalFinal)} (-$totalReduction%)',
            style: const TextStyle(fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w500),
          ),
          if (isTargetSet) ...[
            const SizedBox(height: 4),
            Text(
              '$metCount of ${_batchProcessed.length} images met target size (${humanSize(_targetSizeBytes!)}) within ${_compressionMode.label} quality constraints.',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}
