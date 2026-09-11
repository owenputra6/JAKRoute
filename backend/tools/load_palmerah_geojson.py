"""Convert the surveyed Palmerah GeoJSON (floor 1 + floor 2) into
`station_blocks` / `station_nodes` rows and push them to Supabase.

Usage:
  python tools/load_palmerah_geojson.py --geojson-dir "../new geojson"            # dry run, writes data/palmerah_station_rows.json
  SUPABASE_URL=... SUPABASE_SECRET_KEY=... python tools/load_palmerah_geojson.py --geojson-dir ... --apply

The rows file is the single source of truth for tests; `--apply` replaces every
row for `station_id=palmerah` (nodes first, then blocks) and re-inserts.
Nothing here fabricates data: every block/node comes from a survey feature,
except the two crowd-boundary nodes which define the crowd-simulation corridor.
"""
import argparse
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

from shapely.geometry import shape

STATION = 'palmerah'
FILES = {
    1: ('polygons/Lantai 1 Palmerah Fella.geojson', 'access points/Titik titik penghubung Lantai 1.geojson'),
    2: ('polygons/Lantai 2 Palmerah Fella.geojson', 'access points/Titik Titik Penghubung LT 2.geojson'),
}
# Crowd corridor points are not survey features; they are kept from the
# original 2026-09-09 load so the simulation stays comparable.
CROWD_CORRIDOR = [
    ('Koridor Crowd 01 — Start', [106.79746152248532, -6.207399080319959], 1),
    ('Koridor Crowd 01 — End', [106.79760183449002, -6.207103818662631], 2),
]
SHOPS = ('kopi kenangan', 'alfamart', 'indomaret', "roti'o", 'bakso', 'warung', 'susu bu darmi',
         'creme', 'rayne', 'roti maryam', 'roti o', 'booth', 'cuties catz', 'naruto')


def norm(text):
    return re.sub(r'[^a-z0-9]+', ' ', str(text).lower()).strip()


def classify(name):
    """Return (node_type, kind) from the surveyed label only."""
    n = norm(name)
    if n.startswith('lift'): return 'connector_access', 'elevator'
    if n.startswith('eskalator'): return 'connector_access', 'escalator'
    if n.startswith('tangga'): return 'connector_access', 'stairs'
    if n.startswith('entryexit'): return 'entrance_access', 'entrance'
    if n.startswith('pintu masuk'):
        target = n[len('pintu masuk'):].strip()
        kind = ('toilet' if 'toilet' in target else 'mushola' if 'musala' in target or 'mushola' in target
                else 'lactation_room' if 'laktasi' in target else 'first_aid' if 'p3k' in target else 'access')
        return 'facility_entrance', kind
    if n.startswith('tap in') or n.startswith('tap out'): return 'destination', 'ticket_gate'
    if n == 'atm': return 'destination', 'atm'
    if 'vending' in n or n in ('sprite', 'teh pucuk harum') or 'air minum' in n: return 'destination', 'vending_machine'
    if any(s in n for s in SHOPS): return 'destination', 'shop'
    if n.startswith('kursi'): return 'destination', 'seating'
    return 'destination', 'amenity'


def link_block(name, point, blocks):
    """Exact name match, else nearest block within 3 m (~2.7e-5 deg), else a
    loose name containment. Points are surveyed on their block's edge, so
    nearest is reliable; the loose match only covers far-off labels."""
    target = norm(re.sub(r'\.\d$', '', re.sub(r'^Pintu Masuk ', '', name)))
    for row, geom in blocks:
        if target and target == norm(row['name']):
            return row['id']
    best = min(blocks, key=lambda b: b[1].distance(point))
    if best[1].distance(point) < 2.7e-5:
        return best[0]['id']
    for row, geom in blocks:
        if target and (target in norm(row['name']) or norm(row['name']) in target):
            return row['id']
    return None


def build_rows(geojson_dir):
    blocks, nodes = [], []
    for floor, (poly_file, point_file) in FILES.items():
        polys = json.loads((geojson_dir / poly_file).read_text(encoding='utf-8'))['features']
        points = json.loads((geojson_dir / point_file).read_text(encoding='utf-8'))['features']
        floor_blocks = []
        for no, f in enumerate(polys, 1):
            name = f['properties']['Fasilitas'].strip()
            row = {
                'id': f'{STATION}_lt{floor}_block_{no:03d}', 'station_id': STATION, 'floor': floor, 'source_no': no,
                'name': name, 'block_type': 'rail_track' if norm(name) == 'jalur kereta' else 'facility_block',
                'is_obstacle': True, 'geom': f['geometry'],
                'metadata': {'source_file': poly_file.split('/')[-1], 'source_feature_no': no, 'source_property': 'Fasilitas'},
            }
            floor_blocks.append((row, shape(f['geometry'])))
            blocks.append(row)
        for no, f in enumerate(points, 1):
            name = f['properties']['Access To'].strip()
            node_type, kind = classify(name)
            nodes.append({
                'id': f'{STATION}_lt{floor}_node_{no:03d}', 'station_id': STATION, 'floor': floor, 'source_no': no,
                'name': name, 'node_type': node_type, 'linked_block_id': link_block(name, shape(f['geometry']), floor_blocks),
                'is_routable': True, 'geom': f['geometry'],
                'crowd_zone_id': None, 'crowd_sequence': None, 'crowd_width_m': None,
                'metadata': {'source_file': point_file.split('/')[-1], 'source_feature_no': no,
                             'source_property': 'Access To', 'kind': kind, 'link_method': 'name_or_nearest'},
            })
        if floor == 2:
            base = len(points)
            for i, (label, lonlat, seq) in enumerate(CROWD_CORRIDOR, 1):
                nodes.append({
                    'id': f'{STATION}_lt2_node_{base + i:03d}', 'station_id': STATION, 'floor': 2, 'source_no': base + i,
                    'name': label, 'node_type': 'crowd_boundary', 'linked_block_id': None, 'is_routable': False,
                    'geom': {'type': 'Point', 'coordinates': lonlat},
                    'crowd_zone_id': 'crowd_corridor_01', 'crowd_sequence': seq, 'crowd_width_m': 2.0,
                    'metadata': {'source_file': None, 'source_property': None, 'source_value': None,
                                 'link_method': None, 'note': 'crowd simulation corridor, not a survey feature'},
                })
    return blocks, nodes


def rest(method, url, key, body=None, params=''):
    req = urllib.request.Request(url + params, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={'apikey': key, 'Authorization': 'Bearer ' + key,
                                          'Content-Type': 'application/json', 'Prefer': 'return=minimal'})
    with urllib.request.urlopen(req) as r:
        return r.status


def apply(blocks, nodes):
    url = os.environ['SUPABASE_URL'].rstrip('/') + '/rest/v1/'
    key = os.environ['SUPABASE_SECRET_KEY']
    print('delete nodes', rest('DELETE', url + 'station_nodes', key, params=f'?station_id=eq.{STATION}'))
    print('delete blocks', rest('DELETE', url + 'station_blocks', key, params=f'?station_id=eq.{STATION}'))
    print('insert blocks', rest('POST', url + 'station_blocks', key, blocks))
    print('insert nodes', rest('POST', url + 'station_nodes', key, nodes))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--geojson-dir', required=True)
    ap.add_argument('--apply', action='store_true')
    args = ap.parse_args()
    blocks, nodes = build_rows(Path(args.geojson_dir))
    out = Path(__file__).resolve().parents[1] / 'data' / 'palmerah_station_rows.json'
    out.write_text(json.dumps({'blocks': blocks, 'nodes': nodes}, ensure_ascii=False, indent=1), encoding='utf-8')
    print(f'{len(blocks)} blocks, {len(nodes)} nodes -> {out}')
    for n in nodes:
        print(f"  L{n['floor']} {n['id']:24} {n['node_type']:17} {n['metadata'].get('kind') or '-':15} {n['name']:40} -> {n['linked_block_id']}")
    if args.apply:
        apply(blocks, nodes)
    else:
        print('dry run (pass --apply to write Supabase)', file=sys.stderr)


if __name__ == '__main__':
    main()
