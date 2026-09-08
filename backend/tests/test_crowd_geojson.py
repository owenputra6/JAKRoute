import pytest
from fastapi.testclient import TestClient

from jakroute.api import create_app
from jakroute.config import Settings
from jakroute.crowd import calculate_area_crowd_weight
from jakroute.crowd_simulation import GeoJsonCrowdSimulator
from jakroute.geometry import in_polygon
from jakroute.providers import SupabaseStationClient


def test_palmerah_geojson_creates_exactly_100_weighted_points(site):
    simulator=GeoJsonCrowdSimulator(
        Settings().data_dir/'palmerah_crowd_areas.geojson',
        [106.7974118,-6.20749225],site['floors'][0]['bounds'],100,1234)
    snapshot=simulator.build_snapshot('2026-09-08T00:00:00Z')
    assert snapshot['user_count']==100
    assert len(snapshot['users'])==100
    assert len(snapshot['areas'])==9
    assert len({user['id'] for user in snapshot['users']})==100
    assert all(user['weight']>0 for user in snapshot['users'])
    by_id={area['id']:area for area in snapshot['areas']}
    assert all(in_polygon(user['xy'],by_id[user['area_id']]['polygon']) for user in snapshot['users'])
    assert sum(area['user_count'] for area in snapshot['areas'])==100


def test_geojson_density_uses_source_square_metres(site):
    simulator=GeoJsonCrowdSimulator(
        Settings().data_dir/'palmerah_crowd_areas.geojson',
        [106.7974118,-6.20749225],site['floors'][0]['bounds'],100,1234)
    snapshot=simulator.build_snapshot('2026-09-08T00:00:00Z')
    layer=calculate_area_crowd_weight(snapshot['areas'],snapshot['users'])
    for area in snapshot['areas']:
        expected=sum(user['weight'] for user in snapshot['users'] if user['area_id']==area['id'])/area['area_m2']
        assert layer[area['id']]['density']==pytest.approx(expected)


def test_crowd_snapshot_endpoint_has_same_snapshot_as_routes(tmp_path):
    client=TestClient(create_app(Settings(db_path=str(tmp_path/'state.sqlite3'))))
    crowd=client.get('/crowd/snapshot').json()
    route=client.post('/recommend-route',json={'origin_id':'entrance_west','destination_id':'platform_1'}).json()
    assert crowd['user_count']==100
    assert route['crowd_snapshot_id']==crowd['snapshot_id']
    assert route['ai_insight']['facts'][2]['label']=='Paparan crowd berbobot'


def test_supabase_station_rows_are_validated(monkeypatch):
    rows=[{'id':1,'source_id':'platform_1','name':'Peron asli','category':'platform',
           'latitude':-6.2074,'longitude':106.7974,'floor':1,'area_m2':112}]
    monkeypatch.setattr('jakroute.providers.json_http',lambda *args,**kwargs:rows)
    settings=Settings(station_data_mode='supabase',supabase_url='https://example.supabase.co',supabase_anon_key='anon')
    result=SupabaseStationClient(settings).get_locations()
    assert result['source']=='supabase_rest'
    assert result['locations'][0]['source_id']=='platform_1'
