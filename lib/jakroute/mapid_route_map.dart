import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'models.dart';

/// Existing MAPID style URL is supplied by the host app; routing keys stay in Python.
class MapidRouteMap extends StatefulWidget {
  final String styleUrl;
  final Json catalog;
  final RouteOption? route;
  final int floor;
  const MapidRouteMap({super.key, required this.styleUrl, required this.catalog,
      required this.floor, this.route});
  @override
  State<MapidRouteMap> createState() => _MapidRouteMapState();
}

class _MapidRouteMapState extends State<MapidRouteMap> {
  MapLibreMapController? _controller;
  bool _ready = false, _drawing = false, _pending = false;
  String? _error;

  LatLng _local(List xy) {
    final anchor = widget.catalog['anchor_lonlat'] as List;
    final lon = (anchor[0] as num).toDouble(), lat = (anchor[1] as num).toDouble();
    return LatLng(lat + (xy[1] as num) / 111320,
        lon + (xy[0] as num) / (111320 * math.cos(lat * math.pi / 180)));
  }

  @override
  void didUpdateWidget(covariant MapidRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route || oldWidget.floor != widget.floor || oldWidget.catalog != widget.catalog) {
      unawaited(_render());
    }
  }

  Future<void> _render() async {
    if (!_ready || _controller == null || !mounted) return;
    if (_drawing) { _pending = true; return; }
    _drawing = true;
    try {
      do {
        _pending = false;
        final controller = _controller!;
        await controller.clearLines();
        await controller.clearFills();
        if (!mounted) return;
        final selected = (widget.catalog['floors'] as List).cast<Map>()
            .firstWhere((f) => f['id'] == widget.floor);
        for (final polygon in selected['obstacles'] as List) {
          final rings = (polygon as List).map((ring) =>
              (ring as List).map((p) => _local(p as List)).toList()).toList();
          await controller.addFill(FillOptions(geometry: rings, fillColor: '#324354', fillOpacity: 0.75));
        }
        for (final feature in widget.route?.features ?? <Json>[]) {
          final props = feature['properties'] as Map;
          if (props['scope'] == 'indoor' && props['floor'] != widget.floor) continue;
          final coordinates = (feature['geometry'] as Map)['coordinates'] as List;
          final points = coordinates.map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())).toList();
          if (points.length < 2) continue;
          await controller.addLine(LineOptions(geometry: points, lineColor: props['scope'] == 'outdoor' ? '#c77716' : '#176bdf', lineWidth: 4));
        }
      } while (_pending && mounted);
    } catch (_) {
      if (mounted) setState(() => _error = 'Peta belum dapat memuat jalur. Diagram indoor tetap tersedia.');
    } finally { _drawing = false; }
  }

  @override
  Widget build(BuildContext context) {
    final anchor = widget.catalog['anchor_lonlat'] as List;
    return SizedBox(height: 300, child: Stack(children: [
      MapLibreMap(
        styleString: widget.styleUrl,
        initialCameraPosition: CameraPosition(
            target: LatLng((anchor[1] as num).toDouble(), (anchor[0] as num).toDouble()), zoom: 18),
        onMapCreated: (controller) => _controller = controller,
        onStyleLoadedCallback: () { _ready = true; unawaited(_render()); },
      ),
      if (_error != null) Positioned(left: 8, right: 8, bottom: 8,
          child: Material(color: Colors.white, child: Padding(padding: const EdgeInsets.all(8), child: Text(_error!)))),
    ]));
  }
}
