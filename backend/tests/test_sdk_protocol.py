"""Exercise installed OpenAI SDK serialization over a mocked HTTP transport."""
import json
import httpx
from openai import OpenAI
from jakroute.config import Settings
from jakroute.ai_agent import RouteAgent
from jakroute.service import RouteService

def test_responses_sdk_function_outputs_are_returned_to_model(tmp_path):
    requests=[]
    def handler(request):
        body=json.loads(request.content);requests.append(body)
        name=body.get('text',{}).get('format',{}).get('name')
        if name=='route_intent':
            payload=json.loads(body['input'][1]['content'])
            answer=RouteAgent(Settings()).parse_user_request(payload['request'],payload['context'])
        elif name=='route_explanation':
            payload=json.loads(body['input'][1]['content'])
            answer={'route_id':payload['selected_route_id'],'reason_codes':list(payload['available_reasons'])}
        else: answer={}
        if body.get('tool_choice')=='required':
            jobs=json.loads(body['input'][1]['content'])['jobs']
            output=[dict(type='function_call',id=f'fc_{i}',call_id=f'call_{i}',name=j['name'],arguments=json.dumps(j['arguments']),status='completed') for i,j in enumerate(jobs)]
        else:
            output=[dict(type='message',id='msg_1',role='assistant',status='completed',content=[dict(type='output_text',text=json.dumps(answer),annotations=[])])]
        return httpx.Response(200,json=dict(id=f'resp_{len(requests)}',object='response',created_at=1,model='test-model',status='completed',output=output))
    transport=httpx.MockTransport(handler)
    client=OpenAI(api_key='test-not-a-real-key',http_client=httpx.Client(transport=transport))
    settings=Settings(db_path=str(tmp_path/'state.sqlite3'),agent_mode='openai',openai_model='test-model')
    service=RouteService(settings,RouteAgent(settings,client))
    result=service.recommend({'origin_id':'entrance_west','destination_id':'platform_1','preferences':{'step_free':True}})
    assert result['status']=='ok'
    completion=next(b for b in requests if b.get('tool_choice')=='none')
    outputs=[x for x in completion['input'] if x.get('type')=='function_call_output']
    assert len(outputs)==3
    assert all(json.loads(x['output'])['connectors_used']==['elevator_link'] for x in outputs)
    assert all(b['store'] is False for b in requests)
    client.close()
