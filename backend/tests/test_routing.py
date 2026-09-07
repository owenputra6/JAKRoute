import copy
import pytest
from shapely.geometry import LineString,Polygon
from jakroute.schemas import Preferences
from jakroute.errors import RouteError
from jakroute.crowd import calculate_area_crowd_weight
from jakroute.providers import create_weather_warning

def test_geometry_never_crosses_wall(router,site):
    r=router.route('entrance_west','entrance_east','min_walk')
    obstacle=Polygon(site['floors'][0]['obstacles'][0][0])
    assert LineString([[2,16],[58,16]]).intersects(obstacle) # direct line is invalid
    for f in r['geometry']['features']:
        assert not LineString(f['properties']['local_xy']).intersects(obstacle)
    assert r['walking_m']>56

def test_min_walk_ignores_crowd_choice_but_estimates_actual_time(router,users):
    a=router.route('entrance_west','platform_1','min_walk')
    b=router.route('entrance_west','platform_1','min_walk',users=users)
    assert [x['to'] for x in a['steps']]==[x['to'] for x in b['steps']]
    assert a['walking_m']==b['walking_m']
    assert b['duration_s']>=a['duration_s']

def test_density_is_sum_weights_divided_by_area(site,users):
    layer=calculate_area_crowd_weight(site['crowd_areas'],users)
    assert layer['north']['density']==pytest.approx(sum(u['weight'] for u in users if u['id'].startswith('u'))/600)
    bigger=copy.deepcopy(site['crowd_areas'])
    bigger[0]['polygon']=[[[0,0],[120,0],[120,10],[0,10],[0,0]]]
    assert calculate_area_crowd_weight(bigger,users)['north']['density']==pytest.approx(layer['north']['density']/2)

def test_duplicate_people_rejected(site,users):
    with pytest.raises(RouteError,match='sekali'):
        calculate_area_crowd_weight(site['crowd_areas'],users+[users[0]])

def test_invalid_weights_rejected(site,users):
    users[0]['weight']=float('nan')
    with pytest.raises(RouteError): calculate_area_crowd_weight(site['crowd_areas'],users)

def test_crowding_changes_fastest_route(router,users,incidents):
    a=router.route('entrance_west','platform_1','fastest',incidents=incidents)
    for u in users:
        if u['id'].startswith('u'): u['weight']=40
    b=router.route('entrance_west','platform_1','fastest',incidents=incidents,users=users)
    assert [s['to'] for s in a['steps']]!=[s['to'] for s in b['steps']]

@pytest.mark.parametrize('mode',['best_fit','fastest','min_walk'])
def test_broken_escalator_respected_by_every_mode(router,incidents,mode):
    r=router.route('entrance_west','platform_1',mode,incidents=incidents)
    assert 'escalator_link' not in r['connectors_used']

def test_avoid_stairs_and_broken_escalator_uses_lift(router,incidents):
    r=router.route('entrance_west','platform_1','fastest',preferences={'avoid_stairs':True},incidents=incidents)
    assert r['connectors_used']==['elevator_link']

def test_step_free_excludes_escalator_as_well_as_stairs(router):
    r=router.route('entrance_west','platform_1','fastest',preferences={'step_free':True})
    assert r['connectors_used']==['elevator_link']

def test_minus_one_is_exclusion_not_negative_weight(router,incidents):
    blocked=copy.deepcopy(incidents[0]);blocked.update(resource_id='elevator_link',routing_code=-1,effect='blocked')
    with pytest.raises(RouteError) as err:
        router.route('entrance_west','platform_1','fastest',preferences={'step_free':True},incidents=[blocked])
    assert err.value.code=='no_route'

def test_required_toilet_is_actually_visited(router):
    r=router.route('entrance_west','platform_1','fastest',preferences={'required_facilities':['toilet']})
    assert 'toilet_01' in r['facilities_used']

def test_hard_walk_limit_and_unreachable(router):
    with pytest.raises(RouteError) as err:
        router.route('entrance_west','platform_1','best_fit',preferences={'max_walk_m':2})
    assert err.value.code=='no_route'

def test_no_teleport_between_floors(router):
    r=router.route('entrance_west','platform_1')
    vertical=[s for s in r['steps'] if router.nodes[s['from']]['floor']!=router.nodes[s['to']]['floor']]
    assert vertical and all(s['resource'] for s in vertical)

def test_rain_only_warns_outdoor():
    w={'is_raining':True}
    assert create_weather_warning(w,True)
    assert create_weather_warning(w,False)==[]
    assert create_weather_warning({'is_raining':None},True)
