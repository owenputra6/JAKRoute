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
    if (props['scope'] == 'outdoor') {
      if (walk > 0) out.add('Jalan ${walk.round()} m di Lantai $floor');
      walk = 0;
      final coords = ((f['geometry'] as Map?)?['coordinates'] as List? ?? []).cast<List>();
      double metres = 0;
      for (var i = 1; i < coords.length; i++) {
        metres += _haversine(coords[i - 1], coords[i]);
      }
      out.add('Keluar stasiun, jalan kaki ${metres.round()} m di luar (rute OpenStreetMap)');
      continue;
    }
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
    var via = c?['label'] ?? verbs[props['access']] ?? props['access'];
    // Survey names carry a unit suffix (e.g. "Tangga Peron 1.2") to tell two
    // physical units apart; drop it here since "Naik/Turun" already says the
    // direction and the suffix reads like a confusing version number.
    if (via is String) via = via.replaceFirst(RegExp(r'\.\d+$'), '');
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


double _haversine(List a, List b) {
  const r = 6371000.0;
  final dLat = ((b[1] as num) - (a[1] as num)) * math.pi / 180;
  final dLon = ((b[0] as num) - (a[0] as num)) * math.pi / 180;
  final la1 = (a[1] as num) * math.pi / 180, la2 = (b[1] as num) * math.pi / 180;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(h));
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

/// True when every available alternative is effectively the same path —
/// crowd and personal preferences did not change the route for this pair.
bool routesIdentical(List<RouteOption> routes) {
  final ok = routes.where((r) => r.available).toList();
  if (ok.length < 2) return false;
  final a = ok.first;
  return ok.every((r) => (r.walkingMeters - a.walkingMeters).abs() < 1 && (r.durationSeconds - a.durationSeconds).abs() < 2);
}

const kIdenticalRoutesNote =
    'Ketiga mode menghasilkan jalur yang sama untuk pasangan asal–tujuan ini: hanya satu jalur yang memenuhi batasan, sehingga faktor keramaian dan preferensi personal tidak mengubah rute.';
