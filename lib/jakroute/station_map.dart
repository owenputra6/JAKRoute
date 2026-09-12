import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'models.dart';
import 'route_diagram.dart';

/// Real MAPID basemap (maplibre-gl JS, already loaded by web/index.html) with
/// the surveyed station GeoJSON drawn on top as native map layers: walkable
/// area, obstacle blocks, places, the selected route and simulated crowd.
/// Everything is positioned by real WGS84 coordinates from /catalog and
/// /recommend-route. Falls back to the schematic [RouteDiagram] when no
/// style URL is configured.
///
/// Uses JS interop directly instead of maplibre_gl's Flutter-web binding,
/// which does not paint tiles reliably.
class StationMap extends StatelessWidget {
  const StationMap({super.key, required this.styleUrl, required this.catalog, required this.floor, this.route, this.crowd, this.interactive = true, this.padding = const EdgeInsets.all(40)});
  final String styleUrl;
  final Json catalog;
  final int floor;
  final RouteOption? route;
  final CrowdSnapshot? crowd;
  final bool interactive;
  /// Screen-space padding for camera fitting (e.g. room for overlaid sheets).
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (styleUrl.isEmpty) return RouteDiagram(catalog: catalog, route: route, crowd: crowd, floor: floor);
    return _MapLibreView(styleUrl: styleUrl, catalog: catalog, floor: floor, route: route, crowd: crowd, interactive: interactive, padding: padding);
  }
}

// --- maplibre-gl JS bindings (minimal) -------------------------------------

@JS('maplibregl.Map')
extension type _JsMap._(JSObject _) implements JSObject {
  external factory _JsMap(JSObject options);
  external void on(String event, JSFunction callback);
  external JSObject? getSource(String id);
  external JSObject? getLayer(String id);
  external void addSource(String id, JSObject source);
  external void addLayer(JSObject layer);
  external void fitBounds(JSArray<JSArray<JSNumber>> bounds, JSObject options);
  external void resize();
  external void remove();
  external JSBoolean loaded();
}

extension type _JsGeoJsonSource._(JSObject _) implements JSObject {
  external void setData(JSAny data);
}

class _MapLibreView extends StatefulWidget {
  const _MapLibreView({required this.styleUrl, required this.catalog, required this.floor, this.route, this.crowd, required this.interactive, required this.padding});
  final String styleUrl;
  final Json catalog;
  final int floor;
  final RouteOption? route;
  final CrowdSnapshot? crowd;
  final bool interactive;
  final EdgeInsets padding;

  @override
  State<_MapLibreView> createState() => _MapLibreViewState();
}

class _MapLibreViewState extends State<_MapLibreView> {
  static int _counter = 0;
  late final String _viewType = 'jakroute-basemap-${_counter++}';
  late final web.HTMLDivElement _div;
  _JsMap? _map;
  bool _styleReady = false;
  int _lastFitFloor = -1;
  String? _lastFitRoute;

  @override
  void initState() {
    super.initState();
    _div = web.HTMLDivElement()
      ..style.width = '100%'
      ..style.height = '100%';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) => _div);
    WidgetsBinding.instance.addPostFrameCallback((_) => _create());
  }

  @override
  void dispose() {
    _map?.remove();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _MapLibreView old) {
    super.didUpdateWidget(old);
    if (old.floor != widget.floor || old.route != widget.route || old.catalog != widget.catalog || old.crowd != widget.crowd || old.padding != widget.padding) {
      _sync();
    }
  }

  // Local metres -> WGS84, inverse of backend geometry.lonlat_to_local.
  List<double> _lonlat(List xy) {
    final anchor = widget.catalog['anchor_lonlat'] as List;
    final lon = (anchor[0] as num).toDouble(), lat = (anchor[1] as num).toDouble();
    return [lon + (xy[0] as num) / (111320 * math.cos(lat * math.pi / 180)), lat + (xy[1] as num) / 111320];
  }

  Map<String, dynamic> _fc(List<Map<String, dynamic>> features) => {'type': 'FeatureCollection', 'features': features};

  Map _floorData() => (widget.catalog['floors'] as List).cast<Map>().firstWhere((f) => f['id'] == widget.floor);

  Map<String, dynamic> _walkable() => _fc([
        for (final poly in _floorData()['walkable'] as List)
          {'type': 'Feature', 'properties': {}, 'geometry': {'type': 'Polygon', 'coordinates': [for (final ring in poly as List) [for (final p in ring as List) _lonlat(p as List)]]}},
      ]);

  Map<String, dynamic> _obstacles() => _fc([
        for (final poly in _floorData()['obstacles'] as List)
          {'type': 'Feature', 'properties': {}, 'geometry': {'type': 'Polygon', 'coordinates': [for (final ring in poly as List) [for (final p in ring as List) _lonlat(p as List)]]}},
      ]);

  Map<String, dynamic> _places() => _fc([
        for (final p in (widget.catalog['places'] as List).cast<Map>())
          if ((p['scope'] == 'indoor' && p['floor'] == widget.floor) || p['scope'] == 'outdoor')
            {
              'type': 'Feature',
              'properties': {'label': p['kind'] == 'amenity' || p['kind'] == 'seating' ? '' : p['label'], 'kind': p['kind'], 'outdoor': p['scope'] == 'outdoor'},
              'geometry': {'type': 'Point', 'coordinates': p['source_lonlat'] ?? _lonlat(p['xy'] as List)},
            },
      ]);

  Map<String, dynamic> _routeLines() => _fc([
        for (final f in widget.route?.features ?? const <Json>[])
          if ((f['properties'] as Map)['scope'] != 'indoor' || (f['properties'] as Map)['floor'] == widget.floor)
            {'type': 'Feature', 'properties': {'scope': (f['properties'] as Map)['scope']}, 'geometry': f['geometry']},
      ]);

  Map<String, dynamic> _floorChanges() => _fc([
        for (final f in widget.route?.features ?? const <Json>[])
          if ((f['properties'] as Map)['scope'] == 'indoor' &&
              (f['properties'] as Map)['floor'] == widget.floor &&
              (f['properties'] as Map)['to_floor'] != widget.floor)
            {'type': 'Feature', 'properties': {}, 'geometry': {'type': 'Point', 'coordinates': ((f['geometry'] as Map)['coordinates'] as List).first}},
      ]);

  Map<String, dynamic> _crowdAreas() => _fc([
        for (final a in widget.crowd?.areas ?? const <Json>[])
          if (a['floor'] == widget.floor && a['geojson_geometry'] != null)
            {'type': 'Feature', 'properties': {'density': (a['density'] as num?)?.toDouble() ?? 0, 'label': a['label']}, 'geometry': a['geojson_geometry']},
      ]);

  Map<String, dynamic> _crowd() => _fc([
        for (final u in widget.crowd?.users ?? const <Json>[])
          if (u['floor'] == widget.floor && u['lonlat'] != null)
            {'type': 'Feature', 'properties': {'w': (u['weight'] as num?)?.toDouble() ?? 1}, 'geometry': {'type': 'Point', 'coordinates': u['lonlat']}},
      ]);

  List<List<double>> _bounds(Iterable<List<double>> points) {
    var minLon = 180.0, minLat = 90.0, maxLon = -180.0, maxLat = -90.0;
    for (final p in points) {
      minLon = math.min(minLon, p[0]); maxLon = math.max(maxLon, p[0]);
      minLat = math.min(minLat, p[1]); maxLat = math.max(maxLat, p[1]);
    }
    return [[minLon, minLat], [maxLon, maxLat]];
  }

  void _create() {
    if (!mounted) return;
    final b = (_floorData()['bounds'] as List).cast<num>();
    final c = _lonlat([(b[0] + b[2]) / 2, (b[1] + b[3]) / 2]);
    final map = _JsMap({
      'container': _div,
      'style': widget.styleUrl,
      'center': c,
      'zoom': 18,
      'maxZoom': 22,
      'attributionControl': {'compact': true},
      'interactive': widget.interactive,
      'pitchWithRotate': false,
      'dragRotate': false,
    }.jsify() as JSObject);
    _map = map;
    // Debug handle for the browser console.
    globalContext.setProperty('jakmap'.toJS, map);
    map.on('load', (() {
      _styleReady = true;
      _addLayers();
      _sync(force: true);
    }).toJS);
  }

  void _addSource(String id, Map<String, dynamic> data) => _map!.addSource(id, {'type': 'geojson', 'data': data}.jsify() as JSObject);
  void _addLayer(Map<String, dynamic> layer) => _map!.addLayer(layer.jsify() as JSObject);

  void _addLayers() {
    _addSource('walkable', _walkable());
    _addSource('obstacles', _obstacles());
    _addSource('places', _places());
    _addSource('route', _routeLines());
    _addSource('floor-changes', _floorChanges());
    _addSource('crowd-areas', _crowdAreas());
    _addSource('crowd', _crowd());
    _addLayer({'id': 'walkable-fill', 'type': 'fill', 'source': 'walkable', 'paint': {'fill-color': '#ffffff', 'fill-opacity': 0.88}});
    _addLayer({'id': 'walkable-line', 'type': 'line', 'source': 'walkable', 'paint': {'line-color': '#0058BC', 'line-width': 1.5, 'line-opacity': 0.6}});
    _addLayer({'id': 'obstacles-fill', 'type': 'fill', 'source': 'obstacles', 'paint': {'fill-color': '#324354', 'fill-opacity': 0.85}});
    _addLayer({'id': 'crowd-area-fill', 'type': 'fill', 'source': 'crowd-areas',
        'paint': {'fill-color': '#d04444', 'fill-opacity': ['interpolate', ['linear'], ['get', 'density'], 0, 0.08, 0.5, 0.35]}});
    _addLayer({'id': 'crowd-dots', 'type': 'circle', 'source': 'crowd', 'paint': {'circle-color': '#d04444', 'circle-opacity': 0.75, 'circle-radius': ['+', 2, ['*', 0.7, ['get', 'w']]]}});
    _addLayer({'id': 'route-casing', 'type': 'line', 'source': 'route', 'layout': {'line-cap': 'round', 'line-join': 'round'}, 'paint': {'line-color': '#ffffff', 'line-width': 8}});
    _addLayer({'id': 'route-line', 'type': 'line', 'source': 'route', 'layout': {'line-cap': 'round', 'line-join': 'round'},
        'paint': {'line-color': ['case', ['==', ['get', 'scope'], 'outdoor'], '#c77716', '#0058BC'], 'line-width': 4.5}});
    _addLayer({'id': 'floor-change-dots', 'type': 'circle', 'source': 'floor-changes', 'paint': {'circle-color': '#FFB347', 'circle-radius': 7, 'circle-stroke-color': '#ffffff', 'circle-stroke-width': 2}});
    _addLayer({'id': 'place-dots', 'type': 'circle', 'source': 'places',
        'paint': {'circle-color': ['case', ['get', 'outdoor'], '#c77716', '#127465'], 'circle-radius': ['case', ['get', 'outdoor'], 5, 3.5], 'circle-stroke-color': '#ffffff', 'circle-stroke-width': 1}});
    _addLayer({'id': 'place-labels', 'type': 'symbol', 'source': 'places',
        'layout': {'text-field': ['get', 'label'], 'text-font': ['Roboto Regular'], 'text-size': 10, 'text-offset': [0, 0.9], 'text-anchor': 'top', 'text-max-width': 8},
        'paint': {'text-color': '#223344', 'text-halo-color': '#ffffff', 'text-halo-width': 1.2}});
  }

  void _setData(String id, Map<String, dynamic> data) {
    final src = _map?.getSource(id);
    if (src != null) (src as _JsGeoJsonSource).setData(data.jsify()!);
  }

  void _sync({bool force = false}) {
    if (!_styleReady || _map == null) return;
    _setData('walkable', _walkable());
    _setData('obstacles', _obstacles());
    _setData('places', _places());
    _setData('route', _routeLines());
    _setData('floor-changes', _floorChanges());
    _setData('crowd-areas', _crowdAreas());
    _setData('crowd', _crowd());
    // Camera: follow the route on this floor when one is selected, else the floor.
    final routeId = widget.route?.id;
    final routePts = <List<double>>[
      for (final f in widget.route?.features ?? const <Json>[])
        if ((f['properties'] as Map)['scope'] != 'indoor' || (f['properties'] as Map)['floor'] == widget.floor)
          for (final p in ((f['geometry'] as Map)['coordinates'] as List)) [(p[0] as num).toDouble(), (p[1] as num).toDouble()],
    ];
    if (force || _lastFitFloor != widget.floor || _lastFitRoute != routeId) {
      final b = (_floorData()['bounds'] as List).cast<num>();
      final bounds = routePts.length >= 2
          ? _bounds(routePts)
          : [_lonlat([b[0], b[1]]), _lonlat([b[2], b[3]])];
      _map!.fitBounds(
        bounds.map((p) => p.map((v) => v.toJS).toList().toJS).toList().toJS,
        {'padding': {'top': widget.padding.top, 'bottom': widget.padding.bottom, 'left': widget.padding.left, 'right': widget.padding.right}, 'duration': force ? 0 : 500, 'maxZoom': 20}.jsify() as JSObject,
      );
      _lastFitFloor = widget.floor;
      _lastFitRoute = routeId;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // maplibre needs an explicit resize after the platform view gets laid out.
      scheduleMicrotask(() => _map?.resize());
      return HtmlElementView(viewType: _viewType);
    });
  }
}
