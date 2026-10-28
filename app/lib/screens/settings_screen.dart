import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/update_info.dart';
import '../services/store.dart';
import '../services/update_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../util.dart';
import '../widgets/cards.dart';
import '../widgets/controls.dart';
import '../widgets/logo.dart';
import '../widgets/scaffold.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final updateService = context.watch<UpdateService>();

    return AppScaffold(
      title: 'Settings',
      subtitle: 'Preferences, updates & about',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Files & Storage'),
          PkCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SwitchRow(
                  icon: Icons.photo_library_rounded,
                  title: 'Save to device library',
                  subtitle: 'Automatically copy converted images to Pictures',
                  value: store.saveToGallery,
                  onChanged: store.setSaveToGallery,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('App Updates'),
          _UpdateCard(updateService: updateService),
          const SizedBox(height: 24),
          const SectionHeader('About'),
          PkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const BrandLogo(size: 46),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pocketknife',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(
                          'Version ${updateService.currentVersion?.major ?? 1}.${updateService.currentVersion?.minor ?? 0}.${updateService.currentVersion?.patch ?? 0}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Everyday file tools that run entirely on your device. '
                  'Fast, simple, and 100% offline. Nothing you convert is ever uploaded to a server.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    'by Irshad Akhtar',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.faint, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  final UpdateService updateService;
  const _UpdateCard({required this.updateService});

  @override
  Widget build(BuildContext context) {
    final status = updateService.status;
    final current = updateService.currentVersion;
    final manifest = updateService.latestManifest;

    final versionStr = current != null
        ? 'Version ${current.major}.${current.minor}.${current.patch} (Build ${current.versionCode})'
        : 'Version 1.0.0 (Build 1)';

    return PkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      versionStr,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      updateService.lastChecked != null
                          ? 'Last checked: ${timeAgo(updateService.lastChecked!)}'
                          : 'Check GitHub Releases for updates',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // State-specific presentation
          if (status == UpdateStatus.checking) ...[
            const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
                SizedBox(width: 12),
                Text(
                  'Checking GitHub for updates…',
                  style: TextStyle(fontSize: 13, color: AppColors.muted),
                ),
              ],
            ),
          ] else if (status == UpdateStatus.upToDate) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You are using the latest version of Pocketknife.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: 'Check Again',
              icon: Icons.refresh_rounded,
              expand: true,
              onPressed: () => updateService.checkForUpdates(),
            ),
          ] else if (status == UpdateStatus.updateAvailable && manifest != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accentBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'v${manifest.version}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'New Version Available!',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  if (updateService.isMandatoryUpdate) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 16),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Required Update: Your version is no longer supported.',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF991B1B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    manifest.releaseNotes,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.ink,
                    ),
                  ),
                  if (manifest.fileSizeBytes != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Download size: ${humanSize(manifest.fileSizeBytes!)}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Download Update',
              icon: Icons.download_rounded,
              onPressed: () => updateService.downloadUpdate(),
            ),
          ] else if (status == UpdateStatus.downloading) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Downloading update…',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    Text(
                      '${(updateService.downloadProgress * 100).round()}%',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: updateService.downloadProgress > 0 ? updateService.downloadProgress : null,
                    minHeight: 6,
                    color: AppColors.primary,
                    backgroundColor: const Color(0xFFE2E8F0),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  updateService.totalBytes > 0
                      ? '${humanSize(updateService.downloadedBytes)} / ${humanSize(updateService.totalBytes)}'
                      : humanSize(updateService.downloadedBytes),
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ),
          ] else if (status == UpdateStatus.readyToInstall || status == UpdateStatus.installing) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.successBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update Downloaded',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'The APK has been verified and is ready to install.',
                          style: TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Install Update',
              icon: Icons.system_update_rounded,
              busy: status == UpdateStatus.installing,
              onPressed: () => updateService.installUpdate(context),
            ),
          ] else if (status == UpdateStatus.error) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      updateService.errorMessage ?? 'An error occurred during update.',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GhostButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              expand: true,
              onPressed: () => updateService.checkForUpdates(),
            ),
          ] else ...[
            // Idle state
            SoftButton(
              label: 'Check for Updates',
              icon: Icons.sync_rounded,
              onPressed: () => updateService.checkForUpdates(),
            ),
          ],
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
