import 'package:flutter/material.dart';

import '../mapid_route_map.dart';
import '../models.dart';
import '../route_diagram.dart';
import '../route_steps.dart';
import 'app_theme.dart';
import 'kinds.dart';
import 'widgets.dart';

/// Navigation view (revised UI UX/navigasi_aktif_stasiun_palmerah), without
/// live positioning: there is no indoor GPS, so instead of a moving puck the
/// user steps through the derived instructions manually. Banner, map and
/// step list all come from the returned route geometry and connectors.
class RouteDetailScreen extends StatefulWidget {
  const RouteDetailScreen({super.key, required this.route, required this.catalog, this.mapStyleUrl = ''});

  final RouteOption route;
  final Json catalog;
  final String mapStyleUrl;

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  int? _floor;
  int _step = 0;

  List<int> get _routeFloors {
    final seen = routeFloors(widget.route);
    if (seen.isEmpty) {
      final floors = (widget.catalog['floors'] as List?) ?? [];
      if (floors.isNotEmpty) seen.add((floors.first as Map)['id'] as int? ?? 0);
    }
    return seen;
  }

  /// Floor a step text refers to ("… di Lantai 2", "… ke Lantai 1", "(Lantai 2)").
  int? _floorOf(String step) {
    final m = RegExp(r'Lantai (\d+)').allMatches(step).lastOrNull;
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final route = widget.route, catalog = widget.catalog, mapStyleUrl = widget.mapStyleUrl;
    final floors = _routeFloors;
    final steps = routeSteps(route, catalog);
    final current = steps.isEmpty ? null : steps[_step.clamp(0, steps.length - 1)];
    final floor = _floor ?? (current == null ? floors.first : (_floorOf(current) ?? floors.first));
    final minutes = route.durationSeconds / 60;
    final isChange = current != null && (current.startsWith('Naik') || current.startsWith('Turun'));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: const BrandBar(context: 'Navigasi', leading: BackButton()),
      body: Column(children: [
        // HUD banner: the current instruction.
        Container(
          margin: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(Radii.lg), boxShadow: const [kRaisedShadow]),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Row(children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(color: AppColors.secondary, borderRadius: BorderRadius.circular(Radii.md)),
                  child: Icon(
                    current == null ? Icons.flag : isChange ? (current.startsWith('Naik') ? Icons.arrow_upward : Icons.arrow_downward)
                        : current.startsWith('Tiba') ? Icons.flag : current.startsWith('Mulai') ? Icons.trip_origin : Icons.arrow_forward,
                    color: Colors.white, size: 30,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Langkah ${_step + 1} dari ${steps.length}', style: t.labelSmall?.copyWith(color: Colors.white70)),
                    Text(current ?? 'Rute tanpa langkah', style: t.headlineSmall?.copyWith(color: Colors.white, fontSize: 18)),
                  ]),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xFF00091B),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(Radii.lg)),
              ),
              child: Row(children: [
                const Icon(Icons.route, size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                Expanded(child: Text(route.label, style: t.labelSmall?.copyWith(color: Colors.white))),
                Text(floorLabel(catalog, floor), style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
        // Map.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.lg),
              child: Stack(children: [
                Positioned.fill(
                  child: mapStyleUrl.isNotEmpty
                      ? MapidRouteMap(styleUrl: mapStyleUrl, catalog: catalog, floor: floor, route: route)
                      : RouteDiagram(catalog: catalog, route: route, floor: floor),
                ),
                if (floors.length > 1)
                  Positioned(
                    right: Space.xs, top: Space.xs,
                    child: FloorSwitcher(
                      floors: (catalog['floors'] as List).cast<Map>().where((f) => floors.contains(f['id'])).toList(),
                      active: floor,
                      onChanged: (f) => setState(() => _floor = f),
                    ),
                  ),
              ]),
            ),
          ),
        ),
        // Summary + step list + controls.
        Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
            boxShadow: [kRaisedShadow],
          ),
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.md),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SheetHandle(),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('${minutes < 10 ? minutes.toStringAsFixed(1) : minutes.round()} mnt',
                    style: t.headlineMedium?.copyWith(color: AppColors.success, fontSize: 26)),
                const SizedBox(width: 6),
                Text('(${route.walkingMeters.round()} m jalan kaki)', style: t.bodyMedium?.copyWith(color: AppColors.slate, fontSize: 14)),
              ]),
              Text('Estimasi dari solver; waktu antarlantai adalah asumsi, bukan pengukuran.',
                  style: t.labelSmall?.copyWith(color: AppColors.slateLight)),
              const SizedBox(height: Space.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView(shrinkWrap: true, children: [
                  for (final (i, s) in steps.indexed)
                    InkWell(
                      onTap: () => setState(() { _step = i; _floor = null; }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: Space.xs),
                        decoration: BoxDecoration(
                          color: i == _step ? AppColors.accentLight : Colors.transparent,
                          borderRadius: BorderRadius.circular(Radii.std),
                        ),
                        child: Row(children: [
                          CircleAvatar(
                            radius: 11,
                            backgroundColor: i == _step ? AppColors.secondary : AppColors.surfaceContainer,
                            child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: i == _step ? Colors.white : AppColors.slate)),
                          ),
                          const SizedBox(width: Space.xs),
                          Expanded(child: Text(s, style: t.bodyMedium?.copyWith(fontSize: 14, fontWeight: i == _step ? FontWeight.w600 : FontWeight.w400))),
                        ]),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: Space.xs),
              Row(children: [
                RoundControl(icon: Icons.close, color: AppColors.danger, tooltip: 'Selesai', onTap: () => Navigator.of(context).pop()),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.surfaceContainer, foregroundColor: AppColors.primary, minimumSize: const Size.fromHeight(44)),
                    onPressed: _step == 0 ? null : () => setState(() { _step--; _floor = null; }),
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Kembali'),
                  ),
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: _step >= steps.length - 1 ? null : () => setState(() { _step++; _floor = null; }),
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Berikutnya'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
