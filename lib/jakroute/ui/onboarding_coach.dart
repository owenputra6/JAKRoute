import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'widgets.dart';

class _Step {
  const _Step(this.icon, this.title, this.desc);
  final IconData icon;
  final String title;
  final String desc;
}

const _steps = [
  _Step(Icons.map, 'Peta', 'Lihat posisi, fasilitas, dan rute stasiun langsung di peta interaktif.'),
  _Step(Icons.auto_awesome, 'Tanya AI', 'Tanyakan rute atau fasilitas ke asisten AI, jawab dalam bahasa biasa.'),
  _Step(Icons.storefront, 'Fasilitas', 'Jelajahi semua fasilitas stasiun per lantai, lengkap dengan foto survei.'),
  _Step(Icons.person, 'Profil', 'Atur preferensi perjalanan: hindari tangga, batas jalan kaki, dan lainnya.'),
];

/// First-open coach marks: small contextual popovers pointing at each
/// bottom-nav tab, guiding the user to the app's core value. Shown once
/// (SharedPreferences flag) then never again.
class OnboardingCoach extends StatefulWidget {
  const OnboardingCoach({super.key, required this.child});
  final Widget child;

  @override
  State<OnboardingCoach> createState() => _OnboardingCoachState();
}

class _OnboardingCoachState extends State<OnboardingCoach> {
  static const _flag = 'onboarding_seen_v1';
  bool _show = false;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      if (!(prefs.getBool(_flag) ?? false)) setState(() => _show = true);
    });
  }

  void _dismiss() {
    setState(() => _show = false);
    SharedPreferences.getInstance().then((p) => p.setBool(_flag, true));
  }

  void _next() {
    if (_step >= _steps.length - 1) {
      _dismiss();
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      if (_show) _overlay(context),
    ]);
  }

  Widget _overlay(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final navHeight = 80 + MediaQuery.of(context).padding.bottom;
    final slot = size.width / _steps.length;
    final cx = (slot * _step + slot / 2).clamp(0, size.width);
    final step = _steps[_step];
    final cardWidth = (size.width - Space.gutter * 2).clamp(0, 320).toDouble();
    final left = (cx - cardWidth / 2).clamp(Space.gutter, size.width - cardWidth - Space.gutter);

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _next,
        child: Container(
          color: Colors.black.withOpacity(0.55),
          child: Stack(children: [
            Positioned(
              left: cx - 14,
              bottom: navHeight - 4,
              child: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 28),
            ),
            Positioned(
              left: left,
              width: cardWidth,
              bottom: navHeight + 16,
              child: Material(
                color: Colors.transparent,
                child: SurfaceCard(
                  padding: const EdgeInsets.all(Space.md),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(step.icon, color: AppColors.secondary),
                      const SizedBox(width: Space.xs),
                      Expanded(child: Text(step.title, style: Theme.of(context).textTheme.titleMedium)),
                      Text('${_step + 1}/${_steps.length}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.slate)),
                    ]),
                    const SizedBox(height: Space.xs),
                    Text(step.desc, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: Space.sm),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(onPressed: _dismiss, child: const Text('Lewati')),
                      const SizedBox(width: Space.xs),
                      FilledButton(onPressed: _next, child: Text(_step == _steps.length - 1 ? 'Selesai' : 'Lanjut')),
                    ]),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
