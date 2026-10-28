import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../widgets/cards.dart';
import '../widgets/scaffold.dart';
import 'photo_screen.dart';
import 'docs/merge_pdf_screen.dart';
import 'docs/word_to_pdf_screen.dart';
import 'docs/text_to_pdf_screen.dart';
import 'docs/split_pdf_screen.dart';
import 'docs/compress_pdf_screen.dart';

class DocsScreen extends StatelessWidget {
  const DocsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = <({ToolKind kind, Widget page})>[
      (kind: ToolKind.mergePdf, page: const MergePdfScreen()),
      (kind: ToolKind.imageConverter, page: const PhotoScreen()),
      (kind: ToolKind.wordToPdf, page: const WordToPdfScreen()),
      (kind: ToolKind.textToPdf, page: const TextToPdfScreen()),
      (kind: ToolKind.splitPdf, page: const SplitPdfScreen()),
      (kind: ToolKind.compressPdf, page: const CompressPdfScreen()),
    ];

    return AppScaffold(
      title: 'All Tools',
      subtitle: 'Fast, simple & 100% offline file tools',
      body: Column(
        children: [
          for (var i = 0; i < tools.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == tools.length - 1 ? 0 : 12),
              child: PkCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => tools[i].page),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    ToolIconBadge(kind: tools[i].kind, size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tools[i].kind.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tools[i].kind.blurb,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.faint),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
