import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'tabs/home_tab.dart';
import 'tabs/files_tab.dart';
import 'tabs/activity_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _index,
          children: const [
            HomeTab(),
            FilesTab(),
            ActivityTab(),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.index, required this.onTap});

  static const _items = [
    (activeIcon: Icons.home_rounded, inactiveIcon: Icons.home_outlined, label: 'Home'),
    (activeIcon: Icons.folder_rounded, inactiveIcon: Icons.folder_outlined, label: 'Files'),
    (activeIcon: Icons.access_time_filled_rounded, inactiveIcon: Icons.access_time_rounded, label: 'History'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          i == index ? _items[i].activeIcon : _items[i].inactiveIcon,
                          size: 24,
                          color: i == index ? AppColors.primary : AppColors.muted,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _items[i].label,
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 11.5,
                            fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                            color: i == index ? AppColors.primary : AppColors.muted,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // Active indicator line matching Image 1
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: i == index ? 22 : 0,
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: i == index ? AppColors.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
