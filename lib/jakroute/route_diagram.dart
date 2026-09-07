import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models.dart';

class RouteDiagram extends StatelessWidget {
  final Json catalog;
  final RouteOption? route;
  final int floor;
  const RouteDiagram({super.key, required this.catalog, this.route, required this.floor});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: ColoredBox(color: const Color(0xffeff3f6), child: SizedBox(
      height: 280,
      child: CustomPaint(painter: _StationPainter(catalog, route, floor), child: const SizedBox.expand()),
    )),
  );
}

class _StationPainter extends CustomPainter {
  final Json catalog;
  final RouteOption? route;
  final int floor;
  _StationPainter(this.catalog, this.route, this.floor);

  @override
  void paint(Canvas canvas, Size size) {
    final floors = (catalog['floors'] as List).cast<Map>();
    final selected = floors.firstWhere((f) => f['id'] == floor);
    final bounds = (selected['bounds'] as List).cast<num>();
    final scale = math.min((size.width - 48) / (bounds[2] - bounds[0]),
        (size.height - 56) / (bounds[3] - bounds[1]));
    final dx = (size.width - (bounds[2] - bounds[0]) * scale) / 2;
    final dy = (size.height - (bounds[3] - bounds[1]) * scale) / 2;
    Offset project(List p) => Offset(dx + ((p[0] as num) - bounds[0]) * scale,
        size.height - dy - ((p[1] as num) - bounds[1]) * scale);
    Path polygon(List rings) {
      final path = Path()..fillType = PathFillType.evenOdd;
      for (final ring in rings) {
        final points = (ring as List).map((p) => project(p as List)).toList();
        if (points.isEmpty) continue;
        path.moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) { path.lineTo(point.dx, point.dy); }
        path.close();
      }
      return path;
    }
    for (final poly in selected['walkable'] as List) {
      canvas.drawPath(polygon(poly as List), Paint()..color = Colors.white);
    }
    for (final poly in selected['obstacles'] as List) {
      canvas.drawPath(polygon(poly as List), Paint()..color = const Color(0xff324354));
    }
    final paint = Paint()..color = const Color(0xff176bdf)..strokeWidth = 3..strokeCap = StrokeCap.round;
    for (final feature in route?.features ?? <Json>[]) {
      final props = feature['properties'] as Map;
      if (props['scope'] != 'indoor' || props['floor'] != floor) continue;
      final xy = props['local_xy'] as List?;
      if (xy == null || xy.length < 2) continue;
      canvas.drawLine(project(xy[0] as List), project(xy[1] as List), paint);
      if (props['to_floor'] != floor) canvas.drawCircle(project(xy[0] as List), 6, Paint()..color = Colors.orange);
    }
    final places = (catalog['places'] as List).cast<Map>();
    for (final place in places) {
      if (place['scope'] != 'indoor' || place['floor'] != floor) continue;
      final p = project(place['xy'] as List);
      canvas.drawCircle(p, 3.5, Paint()..color = const Color(0xff127465));
      final label = TextPainter(
        text: TextSpan(text: place['label'] as String, style: const TextStyle(fontSize: 9, color: Color(0xff223344))),
        textDirection: TextDirection.ltr, maxLines: 1,
      )..layout(maxWidth: 105);
      label.paint(canvas, Offset((p.dx + 5).clamp(0, size.width - label.width).toDouble(), p.dy + 4));
    }
  }
  @override
  bool shouldRepaint(covariant _StationPainter oldDelegate) =>
      oldDelegate.route != route || oldDelegate.floor != floor || oldDelegate.catalog != catalog;
}
