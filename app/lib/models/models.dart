import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// The 6 core file tools shown on Home.
enum ToolKind {
  mergePdf,
  imageConverter,
  wordToPdf,
  textToPdf,
  splitPdf,
  compressPdf,
}

extension ToolKindMeta on ToolKind {
  String get id => name;

  IconData get icon {
    switch (this) {
      case ToolKind.mergePdf:
        return Icons.picture_as_pdf_rounded;
      case ToolKind.imageConverter:
        return Icons.image_rounded;
      case ToolKind.wordToPdf:
        return Icons.description_rounded;
      case ToolKind.textToPdf:
        return Icons.article_rounded;
      case ToolKind.splitPdf:
        return Icons.call_split_rounded;
      case ToolKind.compressPdf:
        return Icons.compress_rounded;
    }
  }

  Color get color {
    switch (this) {
      case ToolKind.mergePdf:
        return AppColors.toolMergePdf;
      case ToolKind.imageConverter:
        return AppColors.toolImage;
      case ToolKind.wordToPdf:
        return AppColors.toolWord;
      case ToolKind.textToPdf:
        return AppColors.toolText;
      case ToolKind.splitPdf:
        return AppColors.toolSplit;
      case ToolKind.compressPdf:
        return AppColors.toolCompress;
    }
  }

  Color get tileBg {
    switch (this) {
      case ToolKind.mergePdf:
        return AppColors.toolMergePdfBg;
      case ToolKind.imageConverter:
        return AppColors.toolImageBg;
      case ToolKind.wordToPdf:
        return AppColors.toolWordBg;
      case ToolKind.textToPdf:
        return AppColors.toolTextBg;
      case ToolKind.splitPdf:
        return AppColors.toolSplitBg;
      case ToolKind.compressPdf:
        return AppColors.toolCompressBg;
    }
  }

  String get title {
    switch (this) {
      case ToolKind.mergePdf:
        return 'Merge PDF';
      case ToolKind.imageConverter:
        return 'Image Converter';
      case ToolKind.wordToPdf:
        return 'Word to PDF';
      case ToolKind.textToPdf:
        return 'Text to PDF';
      case ToolKind.splitPdf:
        return 'Split PDF';
      case ToolKind.compressPdf:
        return 'Compress PDF';
    }
  }

  String get blurb {
    switch (this) {
      case ToolKind.mergePdf:
        return 'Combine multiple PDF files';
      case ToolKind.imageConverter:
        return 'Convert images to JPG, PNG, WebP etc.';
      case ToolKind.wordToPdf:
        return 'Convert DOC/DOCX to PDF';
      case ToolKind.textToPdf:
        return 'Convert text or notes to PDF';
      case ToolKind.splitPdf:
        return 'Split PDF into multiple files';
      case ToolKind.compressPdf:
        return 'Reduce file size easily';
    }
  }

  static ToolKind fromId(String id) {
    switch (id) {
      case 'mergePdf':
      case 'docs':
        return ToolKind.mergePdf;
      case 'imageConverter':
      case 'photo':
        return ToolKind.imageConverter;
      case 'wordToPdf':
        return ToolKind.wordToPdf;
      case 'textToPdf':
        return ToolKind.textToPdf;
      case 'splitPdf':
        return ToolKind.splitPdf;
      case 'compressPdf':
        return ToolKind.compressPdf;
      default:
        return ToolKind.mergePdf;
    }
  }
}

/// A completed piece of work, shown in Recent Activity and the History tab.
class ActivityItem {
  final String id;
  final ToolKind kind;
  final String name; // file name, e.g. document.pdf
  final String meta; // e.g. "4 pages • 1.2 MB"
  final String? savedPath;
  final DateTime at;

  ActivityItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.meta,
    this.savedPath,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'meta': meta,
        'savedPath': savedPath,
        'at': at.millisecondsSinceEpoch,
      };

  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
        id: j['id'] as String,
        kind: ToolKindMeta.fromId(j['kind'] as String),
        name: j['name'] as String,
        meta: j['meta'] as String,
        savedPath: j['savedPath'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
}
