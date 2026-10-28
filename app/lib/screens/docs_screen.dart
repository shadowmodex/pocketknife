import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/cards.dart';
import '../widgets/scaffold.dart';
import 'docs/text_to_pdf_screen.dart';
import 'docs/word_to_pdf_screen.dart';
import 'docs/merge_pdf_screen.dart';
import 'docs/split_pdf_screen.dart';
import 'docs/compress_pdf_screen.dart';

class DocsScreen extends StatelessWidget {
  const DocsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = <({IconData icon, String title, String sub, Widget page})>[
      (
        icon: Icons.post_add_rounded,
        title: 'Text to PDF',
        sub: 'Turn notes or text into a clean PDF',
        page: const TextToPdfScreen(),
      ),
      (
        icon: Icons.description_rounded,
        title: 'Word to PDF',
        sub: 'Convert a .docx document to PDF',
        page: const WordToPdfScreen(),
      ),
      (
        icon: Icons.merge_rounded,
        title: 'Merge PDFs',
        sub: 'Combine several PDFs into one',
        page: const MergePdfScreen(),
      ),
      (
        icon: Icons.call_split_rounded,
        title: 'Split / extract',
        sub: 'Pull selected pages into a new PDF',
        page: const SplitPdfScreen(),
      ),
      (
        icon: Icons.compress_rounded,
        title: 'Compress PDF',
        sub: 'Shrink a large PDF to a smaller size',
        page: const CompressPdfScreen(),
      ),
    ];

    return AppScaffold(
      title: 'Docs Toolkit',
      subtitle: 'PDF & Word tools',
      body: Column(
        children: [
          for (var i = 0; i < tools.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == tools.length - 1 ? 0 : 12),
              child: PkCard(
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => tools[i].page)),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    IconTile(
                        icon: tools[i].icon,
                        color: AppColors.toolDocs,
                        bg: AppColors.toolDocsBg,
                        size: 44),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tools[i].title, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(tools[i].sub, style: Theme.of(context).textTheme.bodySmall),
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
