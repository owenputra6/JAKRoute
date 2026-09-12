import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api_client.dart';
import 'app_shell.dart';
import 'app_theme.dart';
import 'onboarding_screen.dart';
import 'widgets.dart';

/// Splash (revised UI UX/splash_screen_jakroute_palmerah). The progress bar
/// is real: it waits for /health and /catalog and shows the actual node
/// count. A signed-in email account goes straight to the shell; otherwise
/// the entry screen (demo / login) follows.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.api, required this.mapStyleUrl});
  final JakRouteApi api;
  final String mapStyleUrl;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  String _status = 'Menghubungi backend…';
  int? _nodes;
  double _progress = 0.1;
  String? _error;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    try {
      final health = await widget.api.health();
      if (!mounted) return;
      setState(() {
        _progress = 0.45;
        _status = 'Solver ${health['agent_mode']} siap. Memuat graf Palmerah…';
      });
      final catalog = await widget.api.catalog();
      if (!mounted) return;
      setState(() {
        _nodes = (catalog['places'] as List?)?.length;
        _progress = 1;
        _status = 'Graf ${(catalog['floors'] as List?)?.length ?? 0} lantai siap';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Backend belum bisa dihubungi. Lanjut ke aplikasi; data akan dimuat ulang.';
        _progress = 1;
      });
    }
    // Keep the brand on screen at least briefly.
    final elapsed = DateTime.now().difference(started);
    if (elapsed < const Duration(milliseconds: 2200)) {
      await Future.delayed(const Duration(milliseconds: 2200) - elapsed);
    }
    if (!mounted) return;
    User? user;
    try {
      user = Supabase.instance.client.auth.currentUser;
    } catch (_) {}
    final signedIn = user != null && !user.isAnonymous && (user.email ?? '').isNotEmpty;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => signedIn
          ? AppShell(api: widget.api, mapStyleUrl: widget.mapStyleUrl)
          : OnboardingScreen(api: widget.api, mapStyleUrl: widget.mapStyleUrl),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -0.2), radius: 1.1, colors: [Color(0xFF0B3A78), Color(0xFF041B3D), Color(0xFF020C1F)]),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: Space.xl),
              const Tag('WebGIS Indoor 2026', color: Color(0x22FFFFFF), fg: Colors.white70),
              const Spacer(flex: 2),
              ScaleTransition(
                scale: Tween(begin: 0.97, end: 1.03).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                child: Container(
                  padding: const EdgeInsets.all(Space.sm),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(Radii.xl),
                    boxShadow: const [kAccentShadow],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.lg),
                    child: Image.asset('assets/logo.png', width: 128, height: 128),
                  ),
                ),
              ),
              const SizedBox(height: Space.lg),
              const Tag('STASIUN PALMERAH', color: Color(0x330058BC), fg: Color(0xFF7DB4FF)),
              const SizedBox(height: Space.sm),
              RichText(
                text: TextSpan(style: t.displayLarge?.copyWith(fontSize: 44, color: Colors.white, letterSpacing: -1), children: const [
                  TextSpan(text: 'JAK'),
                  TextSpan(text: ' Route', style: TextStyle(color: Color(0xFF5E97FE))),
                ]),
              ),
              const SizedBox(height: Space.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                child: Text('Navigasi indoor & wayfinding cerdas berbasis WebGIS & AI multirute',
                    textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: Colors.white70)),
              ),
              const SizedBox(height: Space.xl),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.full),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: _progress),
                      duration: const Duration(milliseconds: 500),
                      builder: (_, v, child) => LinearProgressIndicator(
                        value: v,
                        minHeight: 5,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF5E97FE)),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Row(children: [
                    Expanded(child: Text(_error ?? _status, style: t.labelSmall?.copyWith(color: _error == null ? Colors.white70 : AppColors.warning, fontFamily: 'monospace'))),
                    if (_nodes != null) Text('$_nodes Node', style: t.labelMedium?.copyWith(color: const Color(0xFF7DB4FF), fontFamily: 'monospace')),
                  ]),
                ]),
              ),
              const SizedBox(height: Space.lg),
              Wrap(spacing: Space.xs, children: const [
                Tag('Step-free A*', color: Color(0x1AFFFFFF), fg: Colors.white70),
                Tag('Tanya AI', color: Color(0x1AFFFFFF), fg: Colors.white70),
                Tag('2 lantai + luar', color: Color(0x1AFFFFFF), fg: Colors.white70),
              ]),
              const Spacer(flex: 3),
              Text('•  MAPID WebGIS Competition 2026  •', style: t.labelSmall?.copyWith(color: Colors.white54)),
              const SizedBox(height: Space.lg),
            ],
          ),
        ),
      ),
    );
  }
}
