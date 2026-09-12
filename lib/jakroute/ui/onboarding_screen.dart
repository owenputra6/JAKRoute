import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api_client.dart';
import 'app_shell.dart';
import 'app_theme.dart';
import 'widgets.dart';

/// Entry screen (revised UI UX/masuk_daftar_akun_demo): brand, Masuk/Daftar
/// segmented toggle, an instant-entry demo card (anonymous Supabase session
/// — what judges use), and the real email/password form. Replaces the old
/// onboarding + login + signup trio.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.api, required this.mapStyleUrl});

  final JakRouteApi api;
  final String mapStyleUrl;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signup = false, _loading = false, _obscure = true;
  String? _error, _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _enterApp() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => AppShell(api: widget.api, mapStyleUrl: widget.mapStyleUrl)),
    );
  }

  Future<void> _enterDemo() async {
    setState(() => _loading = true);
    try {
      if (Supabase.instance.client.auth.currentSession == null) {
        await Supabase.instance.client.auth.signInAnonymously();
      }
    } catch (_) {
      // AUTH_MODE=demo on the backend still accepts unauthenticated requests.
    }
    if (!mounted) return;
    _enterApp();
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; _info = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (_signup) {
        final res = await auth.signUp(email: _email.text.trim(), password: _password.text);
        if (!mounted) return;
        if (res.session != null) {
          _enterApp();
        } else {
          setState(() => _info = 'Akun dibuat. Cek email untuk konfirmasi, lalu masuk.');
        }
      } else {
        await auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
        if (!mounted) return;
        _enterApp();
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = _signup ? 'Pendaftaran gagal. Coba lagi.' : 'Login gagal. Periksa email/password.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.lg),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(Space.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(Radii.xl),
                  boxShadow: const [kRaisedShadow],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  child: Image.asset('assets/logo.png', width: 96, height: 96),
                ),
              ),
            ),
            const SizedBox(height: Space.md),
            const Center(child: Tag('WEBGIS INDOOR 2026', icon: Icons.circle, color: AppColors.accentLight, fg: AppColors.secondary)),
            const SizedBox(height: Space.sm),
            Text('JAKRoute Stasiun Palmerah', textAlign: TextAlign.center, style: t.displayLarge?.copyWith(fontSize: 28)),
            const SizedBox(height: Space.xs),
            Text('Navigasi indoor Stasiun Palmerah berbasis AI & WebGIS, akurat hingga level peron.',
                textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: AppColors.slate)),
            const SizedBox(height: Space.lg),
            // Masuk / Daftar segmented toggle.
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: BorderRadius.circular(Radii.lg)),
              child: Row(children: [
                for (final (isSignup, label, icon) in const [(false, 'Masuk', Icons.login), (true, 'Daftar', Icons.person_add_alt)])
                  Expanded(
                    child: Material(
                      color: _signup == isSignup ? AppColors.surfaceContainerLowest : Colors.transparent,
                      borderRadius: BorderRadius.circular(Radii.md),
                      elevation: 0,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(Radii.md),
                        onTap: () => setState(() { _signup = isSignup; _error = null; _info = null; }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: Space.sm),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(icon, size: 18, color: _signup == isSignup ? AppColors.onSurface : AppColors.slate),
                            const SizedBox(width: 6),
                            Text(label, style: t.labelMedium?.copyWith(fontSize: 15, color: _signup == isSignup ? AppColors.onSurface : AppColors.slate)),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: Space.md),
            // Demo card.
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.primary, Color(0xFF0B2E5C)]),
                borderRadius: BorderRadius.circular(Radii.lg),
                boxShadow: const [kRaisedShadow],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Tag('INSTANT ENTRY', icon: Icons.bolt, color: AppColors.secondary, fg: Colors.white),
                  const Spacer(),
                  Text('MAPID Competition 2026', style: t.labelSmall?.copyWith(color: Colors.white70)),
                ]),
                const SizedBox(height: Space.sm),
                Text('Pengujian Langsung WebGIS', style: t.headlineSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text('Akses instan sebagai Guest Rider Palmerah: sesi anonim Supabase, peta indoor dua lantai, dan routing AI tanpa kredensial.',
                    style: t.bodyMedium?.copyWith(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: Space.md),
                FilledButton.icon(
                  onPressed: _loading ? null : _enterDemo,
                  icon: const Icon(Icons.bolt),
                  label: const Text('Masuk Cepat: Akun Demo Palmerah'),
                ),
              ]),
            ),
            const SizedBox(height: Space.md),
            // Real form.
            SurfaceCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Email Pengguna', style: t.labelMedium),
                const SizedBox(height: 6),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(hintText: 'nama@email.com', prefixIcon: Icon(Icons.mail_outline)),
                ),
                const SizedBox(height: Space.sm),
                Text('Kata Sandi', style: t.labelMedium),
                const SizedBox(height: 6),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  onSubmitted: (_) => _loading ? null : _submit(),
                  decoration: InputDecoration(
                    hintText: _signup ? 'Minimal 6 karakter' : '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                ],
                if (_info != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(_info!, style: const TextStyle(color: AppColors.success, fontSize: 13)),
                ],
                const SizedBox(height: Space.md),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00091B)),
                  onPressed: _loading ? null : _submit,
                  icon: _loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.arrow_forward),
                  label: Text(_signup ? 'Daftar ke JAKRoute' : 'Masuk ke JAKRoute'),
                ),
              ]),
            ),
            const SizedBox(height: Space.md),
            const SourceNote(
              'Akun menyimpan sesi Supabase Auth. Preferensi mobilitas (kursi roda, bebas tangga) disimpan di perangkat dan dipakai setiap permintaan rute.',
              icon: Icons.accessible,
            ),
            const SizedBox(height: Space.lg),
            Text('© 2026 JAKRoute Palmerah • MAPID WebGIS Competition',
                textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: AppColors.slateLight)),
          ],
        ),
      ),
    );
  }
}
