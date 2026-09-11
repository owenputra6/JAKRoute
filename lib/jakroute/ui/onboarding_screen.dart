import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api_client.dart';
import 'app_shell.dart';
import 'app_theme.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

/// Mirrors stitch_jakroute_ui_ux_design_system/onboarding_permissions.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.api, required this.mapStyleUrl});

  final JakRouteApi api;
  final String mapStyleUrl;

  Future<void> _enterDemo(BuildContext context) async {
    try {
      if (Supabase.instance.client.auth.currentSession == null) {
        await Supabase.instance.client.auth.signInAnonymously();
      }
    } catch (_) {
      // AUTH_MODE=demo on the backend still accepts unauthenticated requests.
    }
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AppShell(api: api, mapStyleUrl: mapStyleUrl)),
    );
  }

  void _goLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LoginScreen(api: api, mapStyleUrl: mapStyleUrl)),
    );
  }

  void _goSignup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SignupScreen(api: api, mapStyleUrl: mapStyleUrl)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
                child: const Icon(Icons.route, color: Colors.white, size: 40),
              ),
              const SizedBox(height: Space.lg),
              Text('JAKRoute', style: t.displayLarge),
              const SizedBox(height: Space.xs),
              Text(
                'Find what you need.\nKnow how to get there.',
                style: t.bodyLarge?.copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: Space.xl),
              const _PermissionRow(
                icon: Icons.my_location,
                title: 'Akses Lokasi',
                body: 'Dipakai untuk menentukan titik awal rute di dalam stasiun.',
              ),
              const _PermissionRow(
                icon: Icons.groups,
                title: 'Data Keramaian Agregat',
                body: 'Lokasi dianonimkan dan diagregasi. Jejak individu tidak disimpan.',
              ),
              const _PermissionRow(
                icon: Icons.cloud_queue,
                title: 'Cuaca',
                body: 'Ditampilkan ketika rute melewati area outdoor.',
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => _goLogin(context),
                child: const Text('Masuk'),
              ),
              const SizedBox(height: Space.xs),
              OutlinedButton(
                onPressed: () => _goSignup(context),
                child: const Text('Daftar'),
              ),
              const SizedBox(height: Space.xs),
              TextButton(
                onPressed: () => _enterDemo(context),
                child: const Text('Coba akun demo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Icon(icon, color: AppColors.primaryContainer),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.labelMedium),
                const SizedBox(height: 2),
                Text(body, style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
