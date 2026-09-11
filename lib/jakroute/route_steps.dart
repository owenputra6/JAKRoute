import 'dart:math' as math;

import 'models.dart';

/// Turn-by-turn text derived only from the returned geometry: walking
/// length per floor (local metres) and each real connector used.
List<String> routeSteps(RouteOption route, Json catalog) {
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


/// Floors a route touches, in travel order, from its real geometry.
List<int> routeFloors(RouteOption route) {
  final seen = <int>[];
  for (final f in route.features) {
    final props = f['properties'] as Map? ?? {};
    for (final key in ['floor', 'to_floor']) {
      final v = props[key];
      if (v is int && !seen.contains(v)) seen.add(v);
    }
  }
  return seen;
}
