import json
from pathlib import Path

from jakroute.crowd_simulation import NodeCorridorCrowdSimulator
from jakroute.geometry import in_polygon
from jakroute.indoor_routing import IndoorRouter
from jakroute.config import Settings
from jakroute.service import RouteService
from jakroute.station_source import build_station_site


DATA=Path(__file__).resolve().parents[1]/'data'


def station_rows():
    block_features=json.loads((DATA/'palmerah_lt2_blocks.geojson').read_text(encoding='utf-8'))['features']
    node_features=json.loads((DATA/'palmerah_lt2_nodes.geojson').read_text(encoding='utf-8'))['features']
    blocks=[]
    for number,feature in enumerate(block_features,1):
        blocks.append({
            'id':f'palmerah_lt2_block_{number:03d}','station_id':'palmerah',
            'floor':2,'source_no':number,
            'name':feature['properties'].get('Fasilitas') or f'Blok {number}',
            'block_type':'facility_block','is_obstacle':True,
            'geom':feature['geometry'],'metadata':{},
        })
    node_types={**{i:'connector_access' for i in range(1,9)},
        **{i:'entrance_access' for i in range(9,11)},
        **{i:'facility_entrance' for i in range(11,18)},
        18:'destination',19:'crowd_boundary',20:'crowd_boundary'}
    nodes=[]
    for number,feature in enumerate(node_features,1):
        crowd=number in (19,20)
        raw_name=feature['properties'].get('Access To')
        nodes.append({
            'id':f'palmerah_lt2_node_{number:03d}','station_id':'palmerah',
            'floor':2,'source_no':number,
            'name':raw_name or f'Koridor Crowd 01 — {"Start" if number==19 else "End"}',
            'node_type':node_types[number],'linked_block_id':None,
            'is_routable':not crowd,'geom':feature['geometry'],
            'crowd_zone_id':'crowd_corridor_01' if crowd else None,
            'crowd_sequence':number-18 if crowd else None,
            'crowd_width_m':2 if crowd else None,'metadata':{},
        })
    return {'source':'fixture','blocks':blocks,'nodes':nodes}


def test_all_55_blocks_become_obstacles_and_18_points_become_route_anchors():
    site=build_station_site(station_rows())
    assert sum(len(floor['obstacles']) for floor in site['floors'])==55
    assert len(site['places'])==18
    assert {place['source_no'] for place in site['places']}==set(range(1,19))
    assert site['crowd_corridors'][0]['points']
    assert site['routing_geometry_derived'] is True


def test_points_19_20_create_exactly_100_individually_weighted_users():
    site=build_station_site(station_rows())
    crowd=NodeCorridorCrowdSimulator(site['crowd_corridors'],site['anchor_lonlat'],100,19020).build_snapshot('2026-09-09T00:00:00Z')
    assert crowd['user_count']==100
    assert len({user['id'] for user in crowd['users']})==100
    assert len({user['weight'] for user in crowd['users']})>90
    area=crowd['areas'][0]
    assert area['user_count']==100
    assert all(in_polygon(user['xy'],area['polygon']) for user in crowd['users'])
    assert area['density']==round(crowd['total_weight']/area['area_m2'],6)


def test_crowd_corridor_changes_fastest_but_not_plain_shortest_path():
    site=build_station_site(station_rows())
    crowd=NodeCorridorCrowdSimulator(site['crowd_corridors'],site['anchor_lonlat'],100,19020).build_snapshot('2026-09-09T00:00:00Z')
    site['crowd_areas']=[{key:area[key] for key in ('id','floor','area_m2','polygon')} for area in crowd['areas']]
    router=IndoorRouter(site)
    origin='palmerah_lt2_node_004'  # Eskalator Peron 2.2
    destination='palmerah_lt2_node_018'  # Vending Machine 1

    fastest_clear=router.route(origin,destination,'fastest',users=[])
    fastest_crowded=router.route(origin,destination,'fastest',users=crowd['users'])
    plain_clear=router.route(origin,destination,'min_walk',users=[])
    plain_crowded=router.route(origin,destination,'min_walk',users=crowd['users'])

    clear_signature=[step['to'] for step in fastest_clear['steps']]
    crowded_signature=[step['to'] for step in fastest_crowded['steps']]
    assert crowded_signature!=clear_signature
    assert [step['to'] for step in plain_clear['steps']]==[step['to'] for step in plain_crowded['steps']]
    assert plain_clear['walking_m']==plain_crowded['walking_m']
    assert fastest_crowded['crowd_exposure']<plain_crowded['crowd_exposure']
    assert fastest_crowded['duration_s']<plain_crowded['duration_s']


def test_route_service_uses_two_supabase_tables_as_the_live_graph(monkeypatch,tmp_path):
    rows=station_rows()
    rows.update(source='supabase_rest',station_id='palmerah',
                tables={'blocks':'station_blocks','nodes':'station_nodes'})
    monkeypatch.setattr('jakroute.service.SupabaseStationClient.get_station_data',
                        lambda self:rows)
    service=RouteService(Settings(station_data_mode='supabase',
        supabase_url='https://example.supabase.co',supabase_anon_key='anon',
        db_path=str(tmp_path/'forum.sqlite3'),crowd_seed=19020))
    catalog=service.catalog()
    assert catalog['station_data']['counts']=={'blocks':55,'nodes':20}
    assert catalog['routing_geometry_derived'] is True
    result=service.recommend({'origin_id':'palmerah_lt2_node_004',
                              'destination_id':'palmerah_lt2_node_018','message':''})
    assert result['status']=='ok'
    routes={route['mode']:route for route in result['routes']}
    assert routes['fastest']['geometry']!=routes['min_walk']['geometry']
    assert routes['fastest']['crowd_exposure']<routes['min_walk']['crowd_exposure']
    assert result['ai_insight']['facts'][2]['label']=='Paparan crowd berbobot'
