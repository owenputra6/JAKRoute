import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api_client.dart';
import '../models.dart';
import '../user_prefs.dart';
import 'app_theme.dart';
import 'onboarding_screen.dart';
import 'widgets.dart';

/// Profil tab (revised UI UX/profil_pengguna_preferensi). Everything shown is
/// real: the Supabase session (email or anonymous guest), the mobility
/// preferences that are actually sent with every route request
/// (user_prefs.dart), and technical facts read from /catalog and /health.
/// No saved-routes list — the backend has no such feature.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.api, this.mapStyleUrl = ''});
  final JakRouteApi api;
  final String mapStyleUrl;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Json? _catalog;
  Json? _health;
  String? _healthError;
  final _walk = TextEditingController();

  @override
  void initState() {
    super.initState();
    UserPrefs.instance.addListener(_onPrefs);
    _walk.text = UserPrefs.instance.maxWalkM?.round().toString() ?? '';
    widget.api.catalog().then((c) => setState(() => _catalog = c)).catchError((_) {});
    widget.api.health().then((h) => setState(() => _health = h)).catchError((e) => setState(() => _healthError = '$e'));
  }

  void _onPrefs() => setState(() {});

  @override
  void dispose() {
    UserPrefs.instance.removeListener(_onPrefs);
    _walk.dispose();
    super.dispose();
  }

  User? get _user {
    try {
      return Supabase.instance.client.auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  Future<void> _signOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => OnboardingScreen(api: widget.api, mapStyleUrl: widget.mapStyleUrl)),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = UserPrefs.instance;
    final user = _user;
    final anon = user == null || user.isAnonymous || (user.email ?? '').isEmpty;
    final name = anon ? 'Pengguna Demo JAKRoute' : user.email!.split('@').first;
    final places = (_catalog?['places'] as List?)?.length;
    final floors = (_catalog?['floors'] as List?)?.length;
    final connectors = (_catalog?['connectors'] as List?)?.length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const BrandBar(context: 'Profil'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, Space.xl),
        children: [
          SurfaceCard(
            child: Row(children: [
              const UserAvatar(radius: 32),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: t.headlineSmall),
                  Text(anon ? 'Sesi anonim Supabase' : user.email!, style: t.labelSmall?.copyWith(color: AppColors.slate)),
                  const SizedBox(height: 6),
                  Tag(anon ? 'Akun Demo Aktif (Guest Rider)' : 'Akun terdaftar',
                      icon: Icons.circle, color: AppColors.surfaceContainer, fg: AppColors.onSurfaceVariant),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: Space.md),
          SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.tune, color: AppColors.secondary),
                const SizedBox(width: Space.xs),
                Text('Preferensi', style: t.headlineSmall),
              ]),
              const SizedBox(height: Space.xs),
              Text('Dipakai pada setiap permintaan rute (Tanya AI & perencana).', style: t.labelSmall?.copyWith(color: AppColors.slate)),
              const SizedBox(height: Space.md),
              Text('PROFIL UTAMA MOBILITAS', style: t.labelSmall?.copyWith(letterSpacing: 0.6, color: AppColors.onSurfaceVariant)),
              const SizedBox(height: Space.xs),
              Row(children: [
                for (final (key, label, icon) in const [
                  ('wheelchair', 'Kursi Roda', Icons.accessible),
                  ('luggage', 'Bawa Koper', Icons.luggage),
                  ('general', 'Umum / Cepat', Icons.directions_walk),
                ]) ...[
                  Expanded(child: _MobilityTile(label: label, icon: icon, selected: p.mobility == key, onTap: () => p.update(mobility: key))),
                  if (key != 'general') const SizedBox(width: Space.xs),
                ],
              ]),
              const SizedBox(height: Space.sm),
              _SwitchRow(
                icon: Icons.block,
                title: 'Hindari tangga',
                subtitle: 'Lift atau eskalator untuk pindah lantai',
                value: p.avoidStairs,
                onChanged: (v) => p.update(avoidStairs: v),
              ),
              _SwitchRow(
                icon: Icons.elevator_outlined,
                title: 'Bebas anak tangga (lift saja)',
                subtitle: 'Eskalator ikut dihindari — untuk kursi roda / stroller',
                value: p.stepFree,
                onChanged: (v) => p.update(stepFree: v, avoidStairs: v ? true : null),
              ),
              const SizedBox(height: Space.xs),
              TextField(
                controller: _walk,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Batas jalan kaki (meter, kosong = tanpa batas)',
                  prefixIcon: Icon(Icons.straighten),
                ),
                onSubmitted: (v) {
                  final n = double.tryParse(v.trim());
                  p.update(maxWalkM: n, clearWalk: v.trim().isEmpty);
                },
              ),
            ]),
          ),
          const SizedBox(height: Space.md),
          SurfaceCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.terminal, color: AppColors.secondary),
                const SizedBox(width: Space.xs),
                Text('Informasi Teknis & WebGIS', style: t.headlineSmall),
              ]),
              const SizedBox(height: Space.sm),
              _InfoRow('Backend', widget.api.baseUrl.replaceFirst('https://', '')),
              _InfoRow('Geometri sumber', 'Supabase PostGIS (EPSG:4326)'),
              _InfoRow('Jaringan graf', _catalog == null ? '…' : '$places titik survei • $floors lantai • $connectors konektor'),
              _InfoRow('Mode AI', _health?['agent_mode']?.toString() ?? (_healthError == null ? '…' : 'offline')),
              _InfoRow('Data stasiun', _health?['station_data_mode']?.toString() ?? '…'),
              _InfoRow('Cuaca', _health?['weather_mode']?.toString() ?? '…'),
              _InfoRow('Kepadatan', _health == null ? '…' : 'simulasi ${_health!['crowd_user_count']} pengguna'),
              Row(children: [
                Expanded(child: Text('Status solver', style: t.bodyMedium?.copyWith(fontSize: 14, color: AppColors.slate))),
                Tag(_health?['status'] == 'ok' ? 'Python A* Online' : (_healthError == null ? 'Memeriksa…' : 'Offline'),
                    icon: Icons.circle,
                    color: _health?['status'] == 'ok' ? AppColors.accentLight : AppColors.errorContainer,
                    fg: _health?['status'] == 'ok' ? AppColors.secondary : AppColors.error),
              ]),
            ]),
          ),
          const SizedBox(height: Space.md),
          const SourceNote('Lokasi tidak dilacak. Kepadatan adalah simulasi berlabel, bukan data live.', icon: Icons.shield_outlined),
          const SizedBox(height: Space.md),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorContainer, foregroundColor: AppColors.error),
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
            label: Text(anon ? 'Keluar / Ganti Akun (Reset Sesi Demo)' : 'Keluar'),
          ),
        ],
      ),
    );
  }
}

class _MobilityTile extends StatelessWidget {
  const _MobilityTile({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.secondary : AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          child: Column(children: [
            Icon(icon, color: selected ? Colors.white : AppColors.onSurface),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: selected ? Colors.white : AppColors.onSurface)),
          ]),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.title, required this.subtitle, required this.value, required this.onChanged});
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: Space.xs),
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.xs, Space.xs, Space.xs),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: AppColors.accentLight, borderRadius: BorderRadius.circular(Radii.std)),
          child: Icon(icon, size: 20, color: AppColors.secondary),
        ),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.labelMedium?.copyWith(fontSize: 15)),
            Text(subtitle, style: t.labelSmall?.copyWith(color: AppColors.slate)),
          ]),
        ),
        Switch(value: value, onChanged: onChanged, activeThumbColor: Colors.white, activeTrackColor: AppColors.secondary),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(label, style: t.bodyMedium?.copyWith(fontSize: 14, color: AppColors.slate))),
        Expanded(flex: 2, child: Text(value, textAlign: TextAlign.right, style: t.labelMedium?.copyWith(fontSize: 13))),
      ]),
    );
  }
}
