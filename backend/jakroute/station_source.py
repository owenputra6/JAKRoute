"""Build an indoor routing site from Supabase PostGIS block and point rows.

`station_blocks` polygons are hard obstacles. Routable `station_nodes` points
become named graph anchors; crowd-boundary points only define simulation areas.
Because the current source has no explicit walkable-boundary polygon, a marked
prototype boundary is derived from the convex hull of the supplied geometry.
"""
import json
import re

from shapely import wkb, wkt
from shapely.errors import GEOSException
from shapely.geometry import Point, Polygon, shape
from shapely.ops import nearest_points, unary_union

from .errors import RouteError
from .geometry import lonlat_to_local


def decode_postgis_geometry(value, expected_type):
    """Accept PostgREST GeoJSON, JSON text, EWKB hex, or WKT."""
    try:
        if isinstance(value, dict):
            geom = shape(value)
        elif isinstance(value, str):
            raw = value.strip()
            if raw.startswith('{'):
                geom = shape(json.loads(raw))
            elif re.fullmatch(r'(?:\\x)?[0-9a-fA-F]+', raw):
                if raw.startswith('\\x'):
                    raw = raw[2:]
                geom = wkb.loads(bytes.fromhex(raw))
            else:
                geom = wkt.loads(raw)
        else:
            raise TypeError('unsupported geometry payload')
    except (TypeError, ValueError, json.JSONDecodeError, GEOSException) as exc:
        raise RouteError('supabase_geometry', 'Geometry PostGIS tidak dapat dibaca.', 502) from exc
    if geom.geom_type != expected_type or geom.is_empty or not geom.is_valid:
        raise RouteError('supabase_geometry', f'Geometry harus {expected_type} yang valid.', 502)
    return geom


def _local_polygon(geom, anchor):
    exterior = [lonlat_to_local(list(point), anchor) for point in geom.exterior.coords]
    holes = [[lonlat_to_local(list(point), anchor) for point in ring.coords]
             for ring in geom.interiors]
    return Polygon(exterior, holes)


def _rings(geom):
    return [
        [[round(x, 5), round(y, 5)] for x, y in geom.exterior.coords],
        *[[[round(x, 5), round(y, 5)] for x, y in ring.coords]
          for ring in geom.interiors],
    ]


def _kind(row):
    name = str(row.get('name') or '').lower()
    node_type = row.get('node_type')
    if node_type == 'entrance_access':
        return 'entrance'
    for token, kind in (
        ('eskalator', 'escalator'), ('lift', 'elevator'), ('tangga', 'stairs'),
        ('toilet', 'toilet'), ('musala', 'mushola'), ('mushola', 'mushola'),
        ('laktasi', 'lactation_room'), ('p3k', 'first_aid'),
        ('vending', 'vending_machine'),
    ):
        if token in name:
            return kind
    return 'access'


def build_station_site(snapshot, grid_step_m=0.75, clearance_m=0.2,
                       boundary_margin_m=1.5):
    blocks = snapshot.get('blocks') or []
    nodes = snapshot.get('nodes') or []
    if not blocks or not nodes:
        raise RouteError('supabase_schema', 'station_blocks dan station_nodes tidak boleh kosong.', 502)

    if any(not row.get('station_id') for row in blocks + nodes):
        raise RouteError('supabase_schema', 'Setiap row memerlukan station_id.', 502)
    station_ids = {str(row['station_id']) for row in blocks + nodes}
    if len(station_ids) != 1:
        raise RouteError('supabase_schema', 'Data harus berasal dari tepat satu station_id.', 502)
    station_id = station_ids.pop()

    decoded_blocks = []
    for row in blocks:
        if row.get('is_obstacle') is not True:
            raise RouteError('supabase_schema', 'Semua station_blocks harus ditandai sebagai obstacle.', 502)
        decoded_blocks.append((row, decode_postgis_geometry(row.get('geom'), 'Polygon')))
    decoded_nodes = [(row, decode_postgis_geometry(row.get('geom'), 'Point')) for row in nodes]

    anchor_points = [geom for _, geom in decoded_nodes]
    anchor = [
        sum(point.x for point in anchor_points) / len(anchor_points),
        sum(point.y for point in anchor_points) / len(anchor_points),
    ]
    floor_ids = sorted({int(row['floor']) for row, _ in decoded_blocks + decoded_nodes})
    floors = []
    places = []
    corridors = []

    for floor_id in floor_ids:
        floor_blocks = [(row, _local_polygon(geom, anchor))
                        for row, geom in decoded_blocks if int(row['floor']) == floor_id]
        floor_nodes = [(row, Point(lonlat_to_local([geom.x, geom.y], anchor)), geom)
                       for row, geom in decoded_nodes if int(row['floor']) == floor_id]
        if not floor_blocks or not floor_nodes:
            raise RouteError('supabase_schema', f'Lantai {floor_id} membutuhkan block dan node.', 502)

        obstacle_union = unary_union([geom for _, geom in floor_blocks])
        source_geometries = [geom for _, geom in floor_blocks] + [geom for _, geom, _ in floor_nodes]
        walkable = unary_union(source_geometries).convex_hull.buffer(boundary_margin_m, join_style=2)
        if not isinstance(walkable, Polygon) or not walkable.is_valid:
            raise RouteError('supabase_geometry', 'Batas routing turunan tidak valid.', 502)
        free = walkable.difference(obstacle_union.buffer(clearance_m))

        for row, original_point, source_point in floor_nodes:
            if not bool(row.get('is_routable')):
                continue
            routing_point = original_point
            adjustment = 0.0
            if not free.covers(routing_point):
                nearest = nearest_points(original_point, free)[1]
                adjustment = original_point.distance(nearest)
                if adjustment > 0:
                    # Move 2 cm past the boundary into free space. This avoids
                    # floating-point ambiguity for access points drawn on walls.
                    dx=(nearest.x-original_point.x)/adjustment
                    dy=(nearest.y-original_point.y)/adjustment
                    candidate=Point(nearest.x+dx*.02,nearest.y+dy*.02)
                    routing_point=candidate if free.covers(candidate) else nearest
                else:
                    routing_point=nearest
            if adjustment > 5:
                raise RouteError('invalid_place', f"Node {row.get('id')} terlalu jauh dari area bebas.", 502)
            places.append({
                'id': str(row['id']),
                'label': str(row.get('name') or row['id']),
                'xy': [round(routing_point.x, 5), round(routing_point.y, 5)],
                'source_xy': [round(original_point.x, 5), round(original_point.y, 5)],
                'source_lonlat': [
                    round(float(source_point.x), 10),
                    round(float(source_point.y), 10),
                ],
                'routing_adjustment_m': round(adjustment, 4),
                'floor': floor_id,
                'kind': _kind(row),
                'scope': 'indoor',
                'source_no': int(row['source_no']),
                'node_type': row.get('node_type'),
                'linked_block_id': row.get('linked_block_id'),
            })

        grouped = {}
        for row, point, _ in floor_nodes:
            zone = row.get('crowd_zone_id')
            if zone:
                grouped.setdefault(str(zone), []).append((row, point))
        for zone, points in grouped.items():
            points.sort(key=lambda item: int(item[0]['crowd_sequence']))
            if len(points) != 2:
                raise RouteError('supabase_schema', f'Crowd zone {zone} harus memiliki dua titik.', 502)
            widths = {float(row['crowd_width_m']) for row, _ in points}
            if len(widths) != 1 or next(iter(widths)) <= 0:
                raise RouteError('supabase_schema', f'Lebar crowd zone {zone} tidak konsisten.', 502)
            corridors.append({
                'id': zone,
                'label': zone.replace('_', ' ').title(),
                'floor': floor_id,
                'width_m': next(iter(widths)),
                'points': [[round(point.x, 5), round(point.y, 5)] for _, point in points],
            })

        bounds = walkable.bounds
        floors.append({
            'id': floor_id,
            'bounds': [round(value, 5) for value in bounds],
            'walkable': [_rings(walkable)],
            'obstacles': [_rings(geom) for _, geom in floor_blocks],
        })

    if len({place['id'] for place in places}) != len(places):
        raise RouteError('supabase_schema', 'ID station_nodes harus unik.', 502)
    if not corridors:
        raise RouteError('supabase_schema', 'Dua crowd-boundary node belum tersedia.', 502)

    return {
        'id': station_id,
        'label': 'Stasiun Palmerah — Lantai 2',
        'simulated': False,
        'routing_geometry_derived': True,
        'routing_geometry_note': 'Batas walkable diturunkan dari convex hull data; block tetap obstacle keras.',
        'anchor_lonlat': anchor,
        'grid_step_m': float(grid_step_m),
        'clearance_m': float(clearance_m),
        'floor_height_m': 4,
        'floors': floors,
        'places': places,
        'connectors': [],
        'crowd_areas': [],
        'crowd_corridors': corridors,
        'source_counts': {'blocks': len(blocks), 'nodes': len(nodes)},
    }
