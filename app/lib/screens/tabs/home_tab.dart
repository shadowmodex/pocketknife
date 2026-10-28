import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cards.dart';
import '../../widgets/logo.dart';
import '../../widgets/scaffold.dart';
import '../docs_screen.dart';
import '../photo_screen.dart';
import '../settings_screen.dart';
import '../docs/merge_pdf_screen.dart';
import '../docs/word_to_pdf_screen.dart';
import '../docs/text_to_pdf_screen.dart';
import '../docs/split_pdf_screen.dart';
import '../docs/compress_pdf_screen.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  void _openTool(BuildContext context, ToolKind kind) {
    final Widget page = switch (kind) {
      ToolKind.mergePdf => const MergePdfScreen(),
      ToolKind.imageConverter => const PhotoScreen(),
      ToolKind.wordToPdf => const WordToPdfScreen(),
      ToolKind.textToPdf => const TextToPdfScreen(),
      ToolKind.splitPdf => const SplitPdfScreen(),
      ToolKind.compressPdf => const CompressPdfScreen(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top App Header
          Row(
            children: [
              const BrandLogo(size: 42),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pocketknife',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Your everyday file tools',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              CircleIconButton(
                icon: Icons.settings_outlined,
                size: 38,
                iconSize: 20,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Hero Banner (Blue card with 3D folder art)
          const HeroBanner(),
          const SizedBox(height: 22),

          // "All Tools" Section Header with "See All ->"
          Row(
            children: [
              const Text(
                'All Tools',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.2,
                ),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DocsScreen()),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        'See All',
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 15, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 2-Column Grid of 6 Tools matching Image 1
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: Merge PDF, Word to PDF, Split PDF
              Expanded(
                child: Column(
                  children: [
                    ToolCard(
                      kind: ToolKind.mergePdf,
                      onTap: () => _openTool(context, ToolKind.mergePdf),
                    ),
                    const SizedBox(height: 12),
                    ToolCard(
                      kind: ToolKind.wordToPdf,
                      onTap: () => _openTool(context, ToolKind.wordToPdf),
                    ),
                    const SizedBox(height: 12),
                    ToolCard(
                      kind: ToolKind.splitPdf,
                      onTap: () => _openTool(context, ToolKind.splitPdf),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Right Column: Image Converter, Text to PDF, Compress PDF
              Expanded(
                child: Column(
                  children: [
                    ToolCard(
                      kind: ToolKind.imageConverter,
                      onTap: () => _openTool(context, ToolKind.imageConverter),
                    ),
                    const SizedBox(height: 12),
                    ToolCard(
                      kind: ToolKind.textToPdf,
                      onTap: () => _openTool(context, ToolKind.textToPdf),
                    ),
                    const SizedBox(height: 12),
                    ToolCard(
                      kind: ToolKind.compressPdf,
                      onTap: () => _openTool(context, ToolKind.compressPdf),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
