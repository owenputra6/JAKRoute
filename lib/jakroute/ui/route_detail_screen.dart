import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../mapid_route_map.dart';
import '../models.dart';
import '../route_diagram.dart';
import 'app_theme.dart';
import 'kinds.dart';

/// Opened from a route card in chat ("Lihat di peta"): the map/diagram is
/// existing, tested code (mapid_route_map.dart / route_diagram.dart) — this
/// screen only supplies the selected route's floor context around it.
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

  /// Floors the route actually touches, in travel order (from real geometry).
  List<int> get _routeFloors {
    final seen = <int>[];
    for (final f in widget.route.features) {
      final props = f['properties'] as Map? ?? {};
      for (final key in ['floor', 'to_floor']) {
        final v = props[key];
        if (v is int && !seen.contains(v)) seen.add(v);
      }
    }
    if (seen.isEmpty) {
      final floors = (widget.catalog['floors'] as List?) ?? [];
      if (floors.isNotEmpty) seen.add((floors.first as Map)['id'] as int? ?? 0);
    }
    return seen;
  }

  /// Turn-by-turn text derived only from the returned geometry: walking
  /// length per floor (local metres) and each real connector used.
  static List<String> _steps(RouteOption route, Json catalog) {
    final places = {for (final p in (catalog['places'] as List? ?? []).cast<Map>()) p['id']: p};
    final connectors = {for (final c in (catalog['connectors'] as List? ?? []).cast<Map>()) c['id']: c};
    const verbs = {'elevator': 'lift', 'escalator': 'eskalator', 'stairs': 'tangga'};
    final used = (route.data['facilities_used'] as List? ?? []).cast<String>();
    final out = <String>[];
    if (used.isNotEmpty) {
      final o = places[used.first];
      if (o != null) out.add('Mulai dari ${o['label']} (Lantai ${o['floor']})');
    }
    double walk = 0;
    Object? floor;
    for (final f in route.features) {
      final props = f['properties'] as Map? ?? {};
      floor ??= props['floor'];
      final xy = props['local_xy'] as List?;
      if (props['access'] == 'walk') {
        if (xy != null && xy.length == 2) {
          final a = xy[0] as List, b = xy[1] as List;
          walk += math.sqrt(math.pow((b[0] as num) - (a[0] as num), 2) + math.pow((b[1] as num) - (a[1] as num), 2));
        }
        continue;
      }
      if (walk > 0) out.add('Jalan ${walk.round()} m di Lantai $floor');
      walk = 0;
      final c = connectors[props['resource_id']];
      final to = props['to_floor'];
      final up = to is num && floor is num && to > floor;
      final via = c?['label'] ?? verbs[props['access']] ?? props['access'];
      out.add('${up ? 'Naik' : 'Turun'} $via ke Lantai $to');
      floor = to;
    }
    if (walk > 0) out.add('Jalan ${walk.round()} m di Lantai $floor');
    if (used.length > 1) {
      final d = places[used.last];
      if (d != null) out.add('Tiba di ${d['label']} (Lantai ${d['floor']})');
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route, catalog = widget.catalog, mapStyleUrl = widget.mapStyleUrl;
    final floors = _routeFloors;
    final floor = _floor ?? floors.first;
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Rute')),
      body: ListView(
        padding: const EdgeInsets.all(Space.md),
        children: [
          if (floors.length > 1) ...[
            Wrap(spacing: Space.xs, children: [
              for (final f in floors)
                ChoiceChip(label: Text(floorLabel(catalog, f)), selected: floor == f, onSelected: (_) => setState(() => _floor = f)),
            ]),
            const SizedBox(height: Space.sm),
          ],
          if (mapStyleUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.lg),
              child: MapidRouteMap(styleUrl: mapStyleUrl, catalog: catalog, floor: floor, route: route),
            )
          else
            RouteDiagram(catalog: catalog, route: route, floor: floor),
          const SizedBox(height: Space.md),
          Text('Langkah perjalanan', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: Space.xs),
          for (final step in _steps(route, catalog))
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Text('• $step'),
            ),
        ],
      ),
    );
  }
}
