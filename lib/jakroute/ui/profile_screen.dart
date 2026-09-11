import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Mirrors stitch_jakroute_ui_ux_design_system/profile_settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(backgroundColor: AppColors.surface, title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(Space.gutter),
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary,
                child: Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: Space.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pengguna JAKRoute', style: t.headlineSmall),
                  Text(
                    'Komuter Palmerah',
                    style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text('Preferensi Perjalanan', style: t.labelMedium),
          const SizedBox(height: Space.xs),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: true,
                  onChanged: null,
                  title: Text('Hindari tangga', style: t.bodyMedium),
                  subtitle: Text('Prioritaskan lift / ramp', style: t.labelSmall),
                ),
                const Divider(height: 1, color: AppColors.hairline),
                ListTile(
                  title: Text('Batas jalan kaki', style: t.bodyMedium),
                  trailing: Text('500 m', style: t.labelMedium),
                ),
                const Divider(height: 1, color: AppColors.hairline),
                ListTile(
                  title: Text('Toleransi kepadatan', style: t.bodyMedium),
                  trailing: Text('Sedang', style: t.labelMedium),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          Text('Privasi', style: t.labelMedium),
          const SizedBox(height: Space.xs),
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined, color: AppColors.primary),
              title: Text('Lokasi diagregasi & anonim', style: t.bodyMedium),
              subtitle: Text('Jejak individu tidak disimpan.', style: t.labelSmall),
            ),
          ),
          const SizedBox(height: Space.lg),
          Center(
            child: Text(
              'Versi 0.1.0 (scaffold)',
              style: t.labelSmall?.copyWith(color: AppColors.outline),
            ),
          ),
        ],
      ),
    );
  }
}
