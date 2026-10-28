import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Standard page chrome: soft canvas, a lightweight header with an optional
/// back button + trailing action, scrollable body, and the product signature.
class AppScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? action;
  final bool showBack;
  final Widget? bottomBar;
  final bool scrollable;
  final EdgeInsets padding;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.action,
    this.showBack = true,
    this.bottomBar,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          if (showBack) ...[
            _CircleButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                if (subtitle != null)
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );

    final content = scrollable
        ? SingleChildScrollView(
            padding: padding,
            physics: const BouncingScrollPhysics(),
            child: body,
          )
        : Padding(padding: padding, child: body);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            header,
            Expanded(child: content),
            if (bottomBar != null)
              Container(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: bottomBar,
              )
            else
              const _BrandFooter(),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 16, color: AppColors.ink),
        ),
      ),
    );
  }
}

class _BrandFooter extends StatelessWidget {
  const _BrandFooter();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8 + MediaQuery.of(context).padding.bottom, top: 2),
      child: Text(
        'by Irshad Akhtar',
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: AppColors.faint, letterSpacing: 0.4),
      ),
    );
  }
}

/// A small label above a group of controls or a list section.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsets padding;
  const SectionHeader(this.title,
      {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(2, 4, 2, 10)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Friendly placeholder for empty lists (activity, downloads).
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const EmptyState({super.key, required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.faint, size: 24),
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(message,
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
