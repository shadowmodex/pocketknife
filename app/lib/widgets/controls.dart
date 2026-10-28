import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Filled navy primary action, full-width by default, with a busy state.
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool expand;
  const PrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final button = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
        disabledForegroundColor: Colors.white70,
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      onPressed: busy ? null : onPressed,
      child: child,
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Pill segmented control used for the Docs tabs and mode switches.
class SegmentedTabs extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  const SegmentedTabs({super.key, required this.tabs, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: i == index
                        ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))]
                        : null,
                  ),
                  child: Text(
                    tabs[i],
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: i == index ? AppColors.ink : AppColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A selectable row (radio) inside a card — used for quality / bitrate lists.
class OptionTile extends StatelessWidget {
  final String title;
  final String? trailing;
  final bool selected;
  final VoidCallback onTap;
  final bool recommended;
  const OptionTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.recommended = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            _Radio(selected: selected),
            const SizedBox(width: 12),
            Text(title,
                style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: AppColors.ink)),
            if (recommended) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.accentSoft, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: const Text('Recommended',
                    style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent)),
              ),
            ],
            const Spacer(),
            if (trailing != null)
              Text(trailing!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  final bool selected;
  const _Radio({required this.selected});
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: selected ? AppColors.accent : AppColors.lineStrong, width: 2),
      ),
      child: Center(
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          scale: selected ? 1 : 0,
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// Wrap-style single-choice chips (image format, etc.).
class ChoiceChips<T> extends StatelessWidget {
  final List<({T value, String label})> items;
  final T selected;
  final ValueChanged<T> onChanged;
  const ChoiceChips({super.key, required this.items, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final it in items)
          GestureDetector(
            onTap: () => onChanged(it.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: it.value == selected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                    color: it.value == selected ? AppColors.primary : AppColors.line),
              ),
              child: Text(
                it.label,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: it.value == selected ? Colors.white : AppColors.ink,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Outlined secondary action.
class GhostButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;
  const GhostButton(
      {super.key, required this.label, this.icon, this.onPressed, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.lineStrong),
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontWeight: FontWeight.w600, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 7)],
          Text(label),
        ],
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
