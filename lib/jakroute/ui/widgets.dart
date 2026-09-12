import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../facility_photos.dart';
import 'app_theme.dart';
import 'kinds.dart';

/// Shared chrome for the revised UI (revised UI UX/*/screen.png): brand bar,
/// cards, pills, section headers, stat boxes, floor switcher. Everything
/// here is presentational — data binding stays in the screens.

/// Top bar: logo + "JAKRoute" + context word, blue caps station line, avatar.
class BrandBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandBar({super.key, this.context, this.leading, this.onAvatarTap, this.trailing});
  final String? context;
  final Widget? leading;
  final VoidCallback? onAvatarTap;
  /// Extra actions before the avatar (e.g. chat history / new chat).
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext ctx) {
    final t = Theme.of(ctx).textTheme;
    return Container(
      color: AppColors.surfaceContainerLowest,
      padding: EdgeInsets.fromLTRB(Space.md, MediaQuery.of(ctx).padding.top + Space.xs, Space.md, Space.xs),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: Space.xs)],
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.std),
            child: Image.asset('assets/logo.png', width: 36, height: 36, fit: BoxFit.cover),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('JAKRoute', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (context != null) ...[
                      const SizedBox(width: Space.xs),
                      Text(context!, style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ],
                ),
                Text('STASIUN PALMERAH • WEBGIS',
                    style: t.labelSmall?.copyWith(color: AppColors.secondary, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
              ],
            ),
          ),
          if (trailing != null) ...[trailing!, const SizedBox(width: Space.xs)],
          UserAvatar(onTap: onAvatarTap),
        ],
      ),
    );
  }
}

/// Initials from the real Supabase session email; anonymous/guest shows an icon.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, this.onTap, this.radius = 20});
  final VoidCallback? onTap;
  final double radius;

  static String? initials() {
    try {
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email == null || email.isEmpty) return null;
      final name = email.split('@').first;
      final parts = name.split(RegExp(r'[._\-]+')).where((p) => p.isNotEmpty).toList();
      final s = parts.take(2).map((p) => p[0]).join().toUpperCase();
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = initials();
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primary,
        child: s == null
            ? Icon(Icons.person, color: Colors.white, size: radius)
            : Text(s, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.8)),
      ),
    );
  }
}

/// White surface with hairline border and soft shadow (DESIGN.md Level 1).
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(Space.md), this.radius = Radii.lg,
      this.color = AppColors.surfaceContainerLowest, this.border, this.onTap, this.elevated = false});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  final Color? border;
  final VoidCallback? onTap;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? AppColors.hairline),
        boxShadow: elevated ? const [kRaisedShadow] : const [kSurfaceShadow],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(radius), child: box),
    );
  }
}

/// Filter pill: navy when selected, white otherwise. Optional count badge.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.icon, this.selected = false, this.count, this.onTap, this.dotColor});
  final String label;
  final IconData? icon;
  final bool selected;
  final int? count;
  final VoidCallback? onTap;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.onSurface;
    return Material(
      color: selected ? AppColors.primary : AppColors.surfaceContainerLowest,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.primary : AppColors.hairline)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: selected ? Colors.white : AppColors.secondary), const SizedBox(width: 6)],
              if (dotColor != null) ...[
                Container(width: 8, height: 8, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                const SizedBox(width: 6),
              ],
              Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white.withValues(alpha: 0.18) : AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(Radii.full),
                  ),
                  child: Text('$count', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small tinted tag ("LT 2", "Step-free", "Rekomendasi").
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.icon, this.color = AppColors.surfaceContainer, this.fg = AppColors.onSurfaceVariant});
  final String label;
  final IconData? icon;
  final Color color;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// "▍ Title  [badge]" section header.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.badge, this.accent = AppColors.secondary, this.trailing});
  final String title;
  final String? badge;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
      child: Row(
        children: [
          Container(width: 4, height: 20, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: Space.xs),
          Text(title, style: t.headlineSmall),
          if (badge != null) ...[const SizedBox(width: Space.xs), Tag(badge!)],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Grey stat box: small label over bold value.
class StatBox extends StatelessWidget {
  const StatBox({super.key, required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.sm, horizontal: Space.xs),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(Radii.md)),
      child: Column(
        children: [
          Text(label, style: t.labelSmall?.copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: t.labelMedium?.copyWith(fontSize: 16, color: valueColor, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

/// Vertical floor switcher stack (mockup: "L2 Hall / L1 Peron"), highest floor
/// on top. Floors and labels come from the catalog.
class FloorSwitcher extends StatelessWidget {
  const FloorSwitcher({super.key, required this.floors, required this.active, required this.onChanged});
  final List<Map> floors;
  final int active;
  final ValueChanged<int> onChanged;

  static String _short(Map f) => 'L${f['id']}';
  static String _sub(Map f) {
    final label = f['label']?.toString() ?? '';
    final i = label.indexOf('—');
    return i < 0 ? '' : label.substring(i + 1).trim();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: AppColors.hairline),
        boxShadow: const [kRaisedShadow],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in floors.reversed)
            Material(
              color: f['id'] == active ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.std),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.std),
                onTap: () => onChanged(f['id'] as int),
                child: Container(
                  width: 64,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      Text(_short(f),
                          style: t.labelMedium?.copyWith(fontSize: 16, color: f['id'] == active ? Colors.white : AppColors.onSurface)),
                      Text(_sub(f),
                          style: t.labelSmall?.copyWith(
                              fontSize: 10, color: f['id'] == active ? Colors.white70 : AppColors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Round white floating control (locate / 2D / legend buttons in the mockup).
class RoundControl extends StatelessWidget {
  const RoundControl({super.key, required this.icon, this.onTap, this.color = AppColors.secondary, this.tooltip, this.busy = false});
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final String? tooltip;
  /// Shows a small spinner instead of the icon while an action is pending.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final b = Material(
      color: AppColors.surfaceContainerLowest,
      shape: const CircleBorder(side: BorderSide(color: AppColors.hairline)),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: busy
              ? Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color)))
              : Icon(icon, color: color, size: 22),
        ),
      ),
    );
    return tooltip == null ? b : Tooltip(message: tooltip!, child: b);
  }
}

/// Bottom-sheet grab handle.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: Space.xs, bottom: Space.sm),
          decoration: BoxDecoration(color: AppColors.outlineVariant, borderRadius: BorderRadius.circular(Radii.full)),
        ),
      );
}

/// Honest data-source note (survey / simulation labels).
class SourceNote extends StatelessWidget {
  const SourceNote(this.text, {super.key, this.icon = Icons.verified_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
      decoration: BoxDecoration(color: AppColors.surfaceContainer, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.secondary),
        const SizedBox(width: Space.xs),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.onSurface))),
      ]),
    );
  }
}

/// Leading tile for a place: survey photo when one exists, else the kind icon.
class FacilityThumb extends StatelessWidget {
  const FacilityThumb({super.key, required this.place, required this.color, this.size = 44});
  final Map place;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photos = facilityPhotos[place['id']?.toString()];
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.std),
      child: photos != null && photos.isNotEmpty
          ? Image.asset(photos.first, width: size, height: size, fit: BoxFit.cover)
          : Container(
              width: size,
              height: size,
              color: color.withValues(alpha: 0.12),
              child: Icon(iconForKind(place['kind']?.toString()), color: color, size: size / 2),
            ),
    );
  }
}
