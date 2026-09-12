"""Build an indoor routing site from Supabase PostGIS block and point rows.

`station_blocks` polygons are hard obstacles. Routable `station_nodes` points
become named graph anchors; crowd-boundary points only define simulation areas.
Because the current source has no explicit walkable-boundary polygon, a marked
prototype boundary is derived from the convex hull of the supplied geometry.
"""
import json
import math
import re

from shapely import wkb, wkt
from shapely.errors import GEOSException
from shapely.geometry import LineString, MultiPolygon, Point, Polygon, shape
from shapely import affinity
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
    # The loader (tools/load_palmerah_geojson.py) classifies each surveyed
    # label explicitly; the name heuristics below only cover older rows.
    explicit = (row.get('metadata') or {}).get('kind') if isinstance(row.get('metadata'), dict) else None
    if explicit:
        return str(explicit)
    name = str(row.get('name') or '').lower()
    node_type = row.get('node_type')
    if node_type == 'entrance_access':
        return 'entrance'
    for token, kind in (
        ('eskalator', 'escalator'), ('lift', 'elevator'), ('tangga', 'stairs'),
        ('toilet', 'toilet'), ('musala', 'mushola'), ('mushola', 'mushola'),
        ('laktasi', 'lactation_room'), ('p3k', 'first_aid'),
        ('vending', 'vending_machine'), ('atm', 'atm'), ('tap in', 'ticket_gate'), ('pembatas', 'ticket_gate'),
        ('entryexit', 'entrance'), ('kursi', 'seating'), ('tempat sampah', 'amenity'), ('billboard', 'amenity'),
        ('booth', 'shop'), ('alfamart', 'shop'), ('indomaret', 'shop'), ('kopi', 'shop'), ('roti', 'shop'),
        ('bakso', 'shop'), ('warung', 'shop'), ('susu', 'shop'), ('creme', 'shop'), ('rayne', 'shop'),
        ('cuties', 'shop'), ('naruto', 'shop'), ('sprite', 'vending_machine'), ('teh pucuk', 'vending_machine'),
        ('air minum', 'vending_machine'),
    ):
        if token in name:
            return kind
    return 'access'


FLOOR_LABELS = {1: 'Lantai 1 - Peron', 2: 'Lantai 2 - Hall'}


def _block_meta(row, geom, floor_nodes):
    """Kind of a block: from the node linked to it (survey), else its name."""
    kinds = [_kind(node_row) for node_row, _, _ in floor_nodes if node_row.get('linked_block_id') == row.get('id')]
    kinds = [k for k in kinds if k not in ('amenity', 'seating', 'access')]
    kind = kinds[0] if kinds else _kind({'name': row.get('name'), 'metadata': {}})
    if row.get('block_type') == 'rail_track': kind = 'rail_track'
    elif row.get('block_type') == 'gate_barrier': kind = 'ticket_gate'
    c = geom.centroid
    return {'id': row.get('id'), 'name': row.get('name'), 'kind': kind, 'block_type': row.get('block_type'),
            'centroid': [round(c.x, 4), round(c.y, 4)]}


def _paid_boundary(gates, lift_blocks, entrances, extra_m):
    """Wall between the unpaid and paid hall.

    The surveyed gate + pembatas polygons end at the two lift shafts. The lift
    doors are on the paid side (site knowledge, the survey put the access
    points on the unpaid face), so the wall is modelled as: the gate line
    between the shafts, the shafts themselves, and from each shaft's far
    (unpaid) face onward to the outer wall. Everything on the entrance side
    of that chain is unpaid.
    """
    # Axis and thickness come from the turnstile row itself (the largest
    # gate polygon); the short pembatas stubs would skew the rectangle.
    gate = max(gates, key=lambda g: g.area)
    rect = gate.minimum_rotated_rectangle
    coords = list(rect.exterior.coords)[:4]
    edges = [(coords[i], coords[(i + 1) % 4]) for i in range(4)]
    (ax, ay), (bx, by) = max(edges, key=lambda e: Point(e[0]).distance(Point(e[1])))
    length = math.hypot(bx - ax, by - ay)
    ux, uy = (bx - ax) / length, (by - ay) / length
    nx, ny = -uy, ux
    cx, cy = rect.centroid.x, rect.centroid.y
    # Orient the normal towards the paid side (away from the entrances).
    if entrances and sum(nx * (p.x - cx) + ny * (p.y - cy) for p in entrances) > 0:
        nx, ny = -nx, -ny
    def s_of(x, y): return ux * (x - cx) + uy * (y - cy)
    def t_of(x, y): return nx * (x - cx) + ny * (y - cy)
    def box(s0, s1, t0, t1):
        return Polygon([(cx + ux * s + nx * t, cy + uy * s + ny * t) for s, t in ((s0, t0), (s1, t0), (s1, t1), (s0, t1))])
    thickness = max(0.3, max(abs(t_of(*v)) for v in coords))
    far = length / 2 + extra_m
    pieces = list(gates)
    west_edge, east_edge = -far, far
    for block in lift_blocks:
        verts = list(block.exterior.coords)
        ss = [s_of(*v) for v in verts]
        ts = [t_of(*v) for v in verts]
        s0, s1, t_min = min(ss), max(ss), min(ts)
        pieces.append(block)
        if (s0 + s1) / 2 < 0:
            west_edge = max(west_edge, s1)
            pieces.append(box(-far, s0, t_min - thickness, t_min))
        else:
            east_edge = min(east_edge, s0)
            pieces.append(box(s1, far, t_min - thickness, t_min))
    # Straight gate line only between the shafts (or to the outer wall when a
    # side has no shaft).
    pieces.append(box(west_edge, east_edge, -thickness, thickness))
    return unary_union(pieces)


def _stretch_along_axis(geom, extra_m):
    """Extend a thin, elongated shape by `extra_m` at both ends of its long
    axis without changing its thickness."""
    rect = geom.minimum_rotated_rectangle
    coords = list(rect.exterior.coords)[:4]
    edges = [(coords[i], coords[(i + 1) % 4]) for i in range(4)]
    (ax, ay), (bx, by) = max(edges, key=lambda e: Point(e[0]).distance(Point(e[1])))
    length = math.hypot(bx - ax, by - ay)
    angle = math.degrees(math.atan2(by - ay, bx - ax))
    centre = rect.centroid
    aligned = affinity.rotate(geom, -angle, origin=centre)
    factor = (length + 2 * extra_m) / length
    return affinity.rotate(affinity.scale(aligned, factor, 1, origin=centre), angle, origin=centre)

# Travel time per floor change. Walking metres: stairs count as a walk, lifts
# and escalators do not. Survey has no measured times; these are stated
# assumptions, exposed on the connector so the client can show them as such.
CONNECTOR_PARAMS = {
    'elevator': {'duration_s': 45, 'walking_m': 0},
    'escalator': {'duration_s': 30, 'walking_m': 0},
    'stairs': {'duration_s': 30, 'walking_m': 8},
}


def _connectors(places):
    """Pair same-named connector access points across floors.

    `Eskalator Peron 1.1` on floor 1 links to `Eskalator Peron 1.1` on floor 2.
    Escalators are one-way: `.1` runs up (low floor -> high floor), `.2` runs
    down; lifts and stairs are bidirectional.
    """
    groups = {}
    for place in places:
        if place.get('node_type') != 'connector_access':
            continue
        groups.setdefault(place['label'].strip().lower(), []).append(place)
    connectors = []
    for key, group in sorted(groups.items()):
        group.sort(key=lambda p: p['floor'])
        for low, high in zip(group, group[1:]):
            if low['floor'] == high['floor'] or low['kind'] != high['kind'] or low['kind'] not in CONNECTOR_PARAMS:
                continue
            kind = low['kind']
            down = kind == 'escalator' and key.endswith('.2')
            connectors.append({
                'id': f"{low['id']}__{high['id']}",
                'kind': kind,
                'label': low['label'],
                'from': high['id'] if down else low['id'],
                'to': low['id'] if down else high['id'],
                'bidirectional': kind != 'escalator',
                'available': True,
                'timing_assumed': True,
                **CONNECTOR_PARAMS[kind],
            })
    return connectors


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
        # A rail track splits the platform level: west and east halves are not
        # walkable across it. The surveyed track ends at the hull edge, so a
        # stretched copy is cut out of the walkable boundary to close the gap
        # the margin would otherwise leave at both ends. The drawn obstacle
        # stays the surveyed polygon.
        tracks = [geom for row, geom in floor_blocks if row.get('block_type') == 'rail_track']
        if tracks:
            walkable = walkable.difference(unary_union([affinity.scale(t, 1.5, 1.5) for t in tracks]))
        # The tap-gate line separates the paid and unpaid halls. It is drawn as
        # short polygons, but in reality it runs wall to wall and can only be
        # crossed at the turnstiles: stretch it across the hall, then open a
        # passage between the surveyed Tap In / Tap Out points.
        gates = [geom for row, geom in floor_blocks if row.get('block_type') == 'gate_barrier']
        gate_nodes = [point for row, point, _ in floor_nodes if _kind(row) == 'ticket_gate']
        passage = None
        if gates:
            entrances = [point for row, point, _ in floor_nodes if row.get('node_type') == 'entrance_access']
            lifts = [geom for row, geom in floor_blocks
                     if row.get('block_type') != 'gate_barrier' and 'lift' in str(row.get('name', '')).lower()]
            walkable = walkable.difference(_paid_boundary(gates, lifts, entrances, 80))
            if len(gate_nodes) >= 2:
                passage = LineString([gate_nodes[0], gate_nodes[1]]).buffer(1.0)
                walkable = unary_union([walkable, passage])
        if passage is not None:
            floor_blocks = [(row, geom.difference(passage) if row.get('block_type') == 'gate_barrier' else geom)
                            for row, geom in floor_blocks]
            obstacle_union = unary_union([geom for _, geom in floor_blocks])
        walkable_parts = list(walkable.geoms) if isinstance(walkable, MultiPolygon) else [walkable]
        if not walkable.is_valid or any(not isinstance(part, Polygon) for part in walkable_parts):
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
            'label': FLOOR_LABELS.get(floor_id, f'Lantai {floor_id}'),
            'bounds': [round(value, 5) for value in bounds],
            'walkable': [_rings(part) for part in walkable_parts],
            'obstacles': [_rings(part) for _, geom in floor_blocks
                          for part in (geom.geoms if isinstance(geom, MultiPolygon) else [geom])],
            # Parallel to `obstacles`: what each block is, for icons/colours.
            'obstacle_meta': [_block_meta(row, part, floor_nodes) for row, geom in floor_blocks
                              for part in (geom.geoms if isinstance(geom, MultiPolygon) else [geom])],
        })

    if len({place['id'] for place in places}) != len(places):
        raise RouteError('supabase_schema', 'ID station_nodes harus unik.', 502)
    if not corridors:
        raise RouteError('supabase_schema', 'Dua crowd-boundary node belum tersedia.', 502)

    return {
        'id': station_id,
        'label': 'Stasiun Palmerah',
        'simulated': False,
        'routing_geometry_derived': True,
        'routing_geometry_note': 'Batas walkable diturunkan dari convex hull data; block tetap obstacle keras.',
        'anchor_lonlat': anchor,
        'grid_step_m': float(grid_step_m),
        'clearance_m': float(clearance_m),
        'floor_height_m': 4,
        'floors': floors,
        'places': places,
        'connectors': _connectors(places),
        'crowd_areas': [],
        'crowd_corridors': corridors,
        'source_counts': {'blocks': len(blocks), 'nodes': len(nodes)},
    }
