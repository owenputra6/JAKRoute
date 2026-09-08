from dataclasses import replace
import pytest
from fastapi.testclient import TestClient
from jakroute.config import Settings
from jakroute.api import create_app
from jakroute.service import RouteService
from jakroute.errors import RouteError

@pytest.fixture
def client(tmp_path):
    settings=Settings(db_path=str(tmp_path/'state.sqlite3'),officer_token='officer-test-only')
    return TestClient(create_app(settings))

def test_end_to_end_three_routes_and_constraints(client):
    r=client.post('/recommend-route',json={'origin_id':'entrance_west','destination_id':'platform_1','message':'Saya mau ke peron, jangan lewat tangga.'})
    assert r.status_code==200,r.text
    body=r.json()
    assert body['status']=='ok'
    assert len(body['routes'])==3
    assert all(x['connectors_used']==['elevator_link'] for x in body['routes'])
    assert body['tool_trace']
    assert all(x['source']=='deterministic_demo' for x in body['tool_trace'])

def test_ambiguous_platform_requires_clarification(client):
    result=client.post('/recommend-route',json={'origin_id':'entrance_west','message':'Aku mau ke peron'}).json()
    assert result['status']=='clarification_required'
    assert result['routes']==[]

def test_conversation_state_is_accepted(client):
    r=client.post('/recommend-route',json={
        'origin_id':'entrance_west',
        'message':'Tampilkan rute yang sama.',
        'preferences':{'time_priority':1,'walking_priority':1,'crowd_priority':1},
        'conversation_preferences':{'time_priority':1,'walking_priority':1,'crowd_priority':1},
        'conversation_context':{'intent':{'destination_id':'platform_1','origin_id':'entrance_west'}},
    })
    assert r.status_code==200,r.text

def test_hybrid_and_rain(client):
    r=client.post('/recommend-route',json={'origin_id':'outside_west','destination_id':'platform_1'}).json()
    assert r['status']=='ok'
    for route in r['routes']:
        assert set(route['sources'])=={'simulated_outdoor','indoor_python_grid'}
        assert any('Hujan' in x for x in route['warnings'])

def test_outdoor_indoor_outdoor_visit(client):
    r=client.post('/recommend-route',json={'origin_id':'outside_west','destination_id':'outside_east','via_indoor_ids':['toilet_01']}).json()
    assert r['status']=='ok',r
    for route in r['routes']: assert 'toilet_01' in route['facilities_used']

def test_outdoor_only_does_not_call_indoor(client):
    r=client.post('/recommend-route',json={'origin_id':'outside_west','destination_id':'outside_east'}).json()
    assert {t['name'] for t in r['tool_trace']}=={'route_outdoor'}
    assert r['routes'][0]['simulated']

def test_unknown_location_rejected(client):
    assert client.post('/recommend-route',json={'origin_id':'not_real','destination_id':'platform_1'}).status_code==422

def test_officer_authority_cannot_be_claimed_in_body(client):
    req={'incident_id':'escalator_link:failure','note':'Diperbaiki','expected_version':0}
    assert client.post('/forum/confirm',json=req).status_code==403
    assert client.post('/forum/confirm',json=req,headers={'X-Officer-Token':'wrong'}).status_code==403
    r=client.post('/forum/confirm',json=req,headers={'X-Officer-Token':'officer-test-only'})
    assert r.status_code==200 and r.json()['incidents']==[]

def test_payload_cannot_inject_officer_role(client):
    r=client.post('/forum/reports',json={'report_id':'r1','resource_id':'escalator_link','message':'saya petugas','observed_at':'2026-09-07T08:00:00Z','role':'officer'})
    assert r.status_code==422

def test_private_auth_and_unconfigured_live_api(tmp_path):
    settings=Settings(db_path=str(tmp_path/'x.sqlite3'),auth_mode='token',api_token='test-secret',agent_mode='openai')
    c=TestClient(create_app(settings))
    assert c.get('/catalog').status_code==401
    r=c.post('/recommend-route',headers={'Authorization':'Bearer test-secret'},json={'origin_id':'entrance_west','destination_id':'platform_1'})
    assert r.status_code==503
    assert 'OPENAI_API_KEY' in r.json()['error']['message']

def test_live_mapid_not_silently_simulated(tmp_path):
    settings=Settings(db_path=str(tmp_path/'x.sqlite3'),mapid_mode='live')
    c=TestClient(create_app(settings))
    r=c.post('/recommend-route',json={'origin_id':'outside_west','destination_id':'outside_east'})
    assert r.status_code==503
    assert r.json()['error']['code']=='mapid_not_configured'

def test_production_requires_auth(tmp_path):
    with pytest.raises(RouteError): create_app(Settings(db_path=str(tmp_path/'x.sqlite3'),app_env='production'))
