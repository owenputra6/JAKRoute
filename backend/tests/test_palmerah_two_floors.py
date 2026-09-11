"""Floor 1 (peron + rel) and floor 2 (hall) from the surveyed GeoJSON rows.

The rows file is produced by tools/load_palmerah_geojson.py and is exactly
what Supabase holds.
"""
import json
from pathlib import Path

import pytest

from jakroute.errors import RouteError
from jakroute.indoor_routing import IndoorRouter
from jakroute.schemas import Preferences
from jakroute.station_source import build_station_site

ROWS = json.loads((Path(__file__).resolve().parents[1] / 'data' / 'palmerah_station_rows.json').read_text(encoding='utf-8'))
TANGGA_P1_1_L1 = 'palmerah_lt1_node_007'
TANGGA_P1_2_L1 = 'palmerah_lt1_node_008'
TANGGA_P2_1_L1 = 'palmerah_lt1_node_009'
KOPI_KENANGAN_L2 = 'palmerah_lt2_node_029'
ESKALATOR_P1_1_L1 = 'palmerah_lt1_node_003'


@pytest.fixture(scope='module')
def site():
    return build_station_site(ROWS)


@pytest.fixture(scope='module')
def router(site):
    return IndoorRouter(site)


def floors_visited(router, result):
    seen = []
    for step in result['steps']:
        floor = router.nodes[step['to']]['floor']
        if not seen or seen[-1] != floor:
            seen.append(floor)
    return seen


def test_two_floors_with_track_splitting_floor_one(site):
    assert [f['id'] for f in site['floors']] == [1, 2]
    by_id = {f['id']: f for f in site['floors']}
    assert len(by_id[1]['walkable']) == 2, 'rel harus memisahkan peron barat dan timur'
    assert len(by_id[2]['walkable']) == 1
    assert len(site['places']) == 65 and len(site['connectors']) == 8


def test_connectors_pair_same_named_access_points(site):
    kinds = {c['kind']: 0 for c in site['connectors']}
    for c in site['connectors']:
        kinds[c['kind']] += 1
    assert kinds == {'elevator': 2, 'escalator': 2, 'stairs': 4}
    escalators = {c['label']: c for c in site['connectors'] if c['kind'] == 'escalator'}
    assert escalators['Eskalator Peron 1.1']['from'].startswith('palmerah_lt1_')  # .1 goes up
    assert escalators['Eskalator Peron 2.2']['from'].startswith('palmerah_lt2_')  # .2 goes down
    assert all(not c['bidirectional'] for c in escalators.values())
    assert all(c['bidirectional'] for c in site['connectors'] if c['kind'] != 'escalator')


def test_crossing_the_track_must_go_through_floor_two(router):
    result = router.route(TANGGA_P1_1_L1, TANGGA_P2_1_L1, 'min_walk', Preferences())
    assert floors_visited(router, result) == [1, 2, 1]
    assert len(result['connectors_used']) == 2


def test_same_side_stays_on_floor_one(router):
    result = router.route(TANGGA_P1_1_L1, TANGGA_P1_2_L1, 'min_walk', Preferences())
    assert floors_visited(router, result) == [1]
    assert result['connectors_used'] == []


def test_avoid_stairs_and_step_free_pick_the_right_connectors(router):
    stairs_free = router.route(TANGGA_P1_1_L1, TANGGA_P2_1_L1, 'best_fit', Preferences(avoid_stairs=True))
    assert all(router.site['connectors'][i]['kind'] != 'stairs'
               for i, c in enumerate(router.site['connectors']) if c['id'] in stairs_free['connectors_used'])
    step_free = router.route(TANGGA_P1_1_L1, TANGGA_P2_1_L1, 'best_fit', Preferences(step_free=True))
    used = {c['kind'] for c in router.site['connectors'] if c['id'] in step_free['connectors_used']}
    assert used == {'elevator'}


def test_escalator_is_one_way(router):
    up = router.route(ESKALATOR_P1_1_L1, KOPI_KENANGAN_L2, 'fastest', Preferences())
    assert any('lt1_node_003__' in c for c in up['connectors_used'])
    down = router.route(KOPI_KENANGAN_L2, ESKALATOR_P1_1_L1, 'fastest', Preferences())
    assert not any('lt1_node_003__' in c for c in down['connectors_used'])


def test_explicit_kind_metadata_wins(site):
    kinds = {p['label']: p['kind'] for p in site['places']}
    assert kinds['Kopi Kenangan'] == 'shop'
    assert kinds['Tap In'] == 'ticket_gate'
    assert kinds['Kursi Musala Pria'] == 'seating'  # not 'mushola'
    assert kinds['Tempat Sampah Depan Toilet Wanita'] == 'amenity'  # not 'toilet'


ENTRY_1 = 'palmerah_lt2_node_009'
TOILET_DIFABEL = 'palmerah_lt2_node_015'
LIFT_P1_L2 = 'palmerah_lt2_node_001'


def _visits_turnstile(router, result):
    from shapely.geometry import LineString, Point
    places = {p['label']: p for p in router.site['places'] if p['floor'] == 2}
    passage = LineString([places['Tap In']['xy'], places['Tap Out']['xy']]).buffer(1.5)
    return any(passage.contains(Point(router.nodes[s['to']]['xy'])) for s in result['steps'])


def test_entrance_to_paid_hall_goes_through_the_tap_gate(router):
    result = router.route(ENTRY_1, TOILET_DIFABEL, 'min_walk', Preferences())
    assert floors_visited(router, result) == [2]
    assert _visits_turnstile(router, result), 'rute harus lewat Tap In/Tap Out, bukan memutar sisi luar'


def test_lifts_are_on_the_paid_side(router):
    result = router.route(ENTRY_1, LIFT_P1_L2, 'min_walk', Preferences())
    assert _visits_turnstile(router, result)
