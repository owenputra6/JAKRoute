import 'package:flutter/material.dart';

import '../mapid_route_map.dart';
import '../models.dart';
import '../route_diagram.dart';
import 'app_theme.dart';

/// Opened from a route card in chat ("Lihat di peta"): the map/diagram is
/// existing, tested code (mapid_route_map.dart / route_diagram.dart) — this
/// screen only supplies the selected route's floor context around it.
class RouteDetailScreen extends StatelessWidget {
  const RouteDetailScreen({super.key, required this.route, required this.catalog, this.mapStyleUrl = ''});

  final RouteOption route;
  final Json catalog;
  final String mapStyleUrl;

  int get _floor {
    final floors = (catalog['floors'] as List?) ?? [];
    if (floors.isEmpty) return 0;
    return (floors.first as Map)['id'] as int? ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detail Rute')),
      body: ListView(
        padding: const EdgeInsets.all(Space.md),
        children: [
          if (mapStyleUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.lg),
              child: MapidRouteMap(styleUrl: mapStyleUrl, catalog: catalog, floor: _floor, route: route),
            )
          else
            RouteDiagram(catalog: catalog, route: route, floor: _floor),
          const SizedBox(height: Space.md),
          Text('Langkah perjalanan', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: Space.xs),
          for (final step in route.data['steps'] as List? ?? [])
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Text('• ${step.toString()}'),
            ),
        ],
      ),
    );
  }
}
