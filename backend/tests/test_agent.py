import json
from types import SimpleNamespace
from jakroute.ai_agent import RouteAgent,TOOLS
from jakroute.config import Settings
from jakroute.service import RouteService

class FakeResponses:
    """Contract test double, not an AI model and not a live API evaluation."""
    def __init__(self): self.calls=[]
    def create(self,**kwargs):
        self.calls.append(kwargs)
        if kwargs.get('tool_choice')=='none': return SimpleNamespace(output=[],output_text='Selesai')
        if kwargs.get('tools'):
            payload=json.loads(kwargs['input'][1]['content'])
            return SimpleNamespace(output=[SimpleNamespace(type='function_call',name=j['name'],arguments=json.dumps(j['arguments']),call_id=f'call_{i}') for i,j in enumerate(payload['jobs'])])
        name=kwargs['text']['format']['name']; payload=json.loads(kwargs['input'][1]['content'])
        if name=='route_intent':
            agent=RouteAgent(Settings())
            result=agent.parse_user_request(payload['request'],payload['context'])
        else: result={'route_id':payload['selected_route_id'],'reason_codes':list(payload['available_reasons'])}
        return SimpleNamespace(output=[],output_text=json.dumps(result))

def test_real_tool_dispatch_contract_with_mock_model(tmp_path):
    fake=FakeResponses()
    settings=Settings(db_path=str(tmp_path/'x.sqlite3'),agent_mode='openai',openai_model='test-model')
    agent=RouteAgent(settings,client=SimpleNamespace(responses=fake))
    service=RouteService(settings,agent=agent)
    body=service.recommend({'origin_id':'entrance_west','destination_id':'platform_1','preferences':{'avoid_stairs':True}})
    assert body['status']=='ok'
    assert {x['name'] for x in body['tool_trace']}=={'route_indoor_plain','route_indoor_personalized'}
    assert all(r['connectors_used']==['elevator_link'] for r in body['routes'])
    assert len(fake.calls)>=3

def test_model_cannot_relax_explicit_constraints(site):
    fake=FakeResponses();agent=RouteAgent(Settings(agent_mode='openai'),SimpleNamespace(responses=fake))
    result=agent.parse_user_request({'origin_id':'entrance_west','destination_id':'platform_1','preferences':{'step_free':True,'max_walk_m':120}}, {'places':site['places']})
    assert result['preferences']['step_free'] is True
    assert result['preferences']['max_walk_m']==120

def test_only_three_tools_and_strict_schemas():
    assert len(TOOLS)==3
    for t in TOOLS:
        assert t['strict'] and t['parameters']['additionalProperties'] is False
        assert set(t['parameters']['required'])==set(t['parameters']['properties'])
