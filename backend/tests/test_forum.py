import json
import pytest
import httpx
from pathlib import Path
from types import SimpleNamespace
from jakroute.forum_state import ForumStore,DemoSummarizer
from jakroute.forum_state import OllamaSummarizer,OpenAISummarizer
from jakroute.config import Settings
from jakroute.errors import RouteError

DATA=Path(__file__).resolve().parents[1]/'data'
REPORTS=json.loads((DATA/'forum_reports.json').read_text())

def test_state_persists_and_passenger_cannot_resolve(tmp_path):
    path=tmp_path/'state.sqlite3'; store=ForumStore(path); ai=DemoSummarizer()
    for r in REPORTS[:3]: store.update(r,ai.summarize(r,store.snapshot()))
    snap=ForumStore(path).snapshot()
    assert len(snap['incidents'])==1
    inc=snap['incidents'][0]
    assert inc['status']=='awaiting_officer_confirmation'
    assert inc['effect']=='unavailable'
    assert inc['resolution_claimed'] is True

def test_dedup_and_conflicting_report_id(tmp_path):
    store=ForumStore(tmp_path/'state.sqlite3'); r=REPORTS[0]; x=DemoSummarizer().summarize(r,{})
    assert store.update(r,x)
    assert store.update(r,x) is False
    assert store.snapshot()['version']==1
    with pytest.raises(RouteError): store.update({**r,'message':'different'},x)

def test_severe_stays_blocked_after_milder_report(tmp_path):
    store=ForumStore(tmp_path/'state.sqlite3');r=REPORTS[3]; x=DemoSummarizer().summarize(r,{})
    store.update(r,x)
    store.update({**r,'report_id':'new','observed_at':'2026-09-07T08:26:00Z'}, {**x,'effect':'caution','severe':False})
    assert store.snapshot()['incidents'][0]['routing_code']==-1
    assert store.snapshot()['incidents'][0]['effect']=='blocked'

def test_officer_confirmation_and_late_reports(tmp_path):
    store=ForumStore(tmp_path/'state.sqlite3');r=REPORTS[0]; x=DemoSummarizer().summarize(r,{})
    store.update(r,x)
    store.confirm('escalator_link:failure','verified-officer','Sudah diperbaiki',1,'2026-09-07T08:30:00Z')
    assert not store.snapshot()['incidents']
    store.update({**r,'report_id':'late','observed_at':'2026-09-07T08:29:00Z'},x)
    assert not store.snapshot()['incidents']
    store.update({**r,'report_id':'recurrence','observed_at':'2026-09-07T08:31:00Z'},x)
    assert store.snapshot()['incidents'][0]['status']=='active'

def test_stale_officer_confirmation_rejected(tmp_path):
    store=ForumStore(tmp_path/'state.sqlite3');r=REPORTS[0]
    store.update(r,DemoSummarizer().summarize(r,{}))
    with pytest.raises(RouteError) as err: store.confirm('escalator_link:failure','officer','fixed',0)
    assert err.value.code=='state_conflict'

def test_malformed_ai_output_does_not_change_state(tmp_path):
    store=ForumStore(tmp_path/'state.sqlite3')
    with pytest.raises(RouteError): store.update(REPORTS[0],{'summary':'fixed'})
    assert store.snapshot()['version']==0

def test_missing_ollama_model_has_actionable_error(monkeypatch):
    class FakeClient:
        def __enter__(self): return self
        def __exit__(self,*args): return False
        def post(self,*args,**kwargs):
            return httpx.Response(404,json={'error':'model gemma4:e4b not found'},request=httpx.Request('POST','http://127.0.0.1:11434/api/chat'))
    monkeypatch.setattr('jakroute.forum_state.httpx.Client',lambda **kwargs: FakeClient())
    with pytest.raises(RouteError) as error:
        OllamaSummarizer(Settings(ollama_model='gemma4:e4b')).summarize(REPORTS[0],{})
    assert error.value.code=='ollama_model_not_found'
    assert 'ollama pull gemma4:e4b' in error.value.message

def test_openai_forum_summary_uses_schema_and_output_cap():
    extraction={'summary':'Eskalator rusak.','category':'failure','effect':'unavailable','severe':False,'resolution_claimed':False}
    class Responses:
        def __init__(self): self.kwargs=None
        def create(self,**kwargs):
            self.kwargs=kwargs
            return SimpleNamespace(output_text=json.dumps(extraction))
    responses=Responses()
    client=SimpleNamespace(responses=responses)
    result=OpenAISummarizer(Settings(openai_api_key='test',openai_model='gpt-5-mini'),client).summarize(REPORTS[0],{})
    assert result==extraction
    assert responses.kwargs['max_output_tokens']==160
    assert responses.kwargs['store'] is False
    assert responses.kwargs['text']['format']['type']=='json_schema'
