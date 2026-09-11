from contextlib import asynccontextmanager
from typing import Literal
import secrets
import time
import threading
from collections import defaultdict,deque
import httpx
from fastapi import FastAPI,Depends,Header,Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel,Field,ConfigDict
from .config import Settings
from .service import RouteService
from .errors import RouteError
from .forum_state import timestamp
from .schemas import Preferences

class StrictModel(BaseModel):
    model_config=ConfigDict(extra='forbid')

class RouteRequest(StrictModel):
    message:str=Field(default='',max_length=2000)
    origin_id:str|None=Field(default=None,max_length=100)
    destination_id:str|None=Field(default=None,max_length=100)
    default_platform_id:str|None=Field(default=None,max_length=100)
    via_indoor_ids:list[str]=Field(default_factory=list,max_length=4)
    focus_mode:Literal['best_fit','fastest','min_walk']|None=None
    preferences:dict=Field(default_factory=dict)
    # Conversation state is client-owned state returned by the previous route
    # response. It lets Flutter continue a turn without repeating the intent.
    conversation_preferences:dict=Field(default_factory=dict)
    conversation_context:dict=Field(default_factory=dict)

class ForumReport(StrictModel):
    report_id:str=Field(min_length=1,max_length=100)
    resource_id:str=Field(min_length=1,max_length=100)
    observed_at:str=Field(max_length=50)
    message:str=Field(min_length=1,max_length=4000)

class Confirmation(StrictModel):
    incident_id:str=Field(min_length=1,max_length=150)
    note:str=Field(min_length=1,max_length=1500)
    expected_version:int=Field(ge=0)

def create_app(settings=None,service=None):
    settings=settings or Settings.from_env()
    # Refuse unsafe production configurations also when instantiated directly.
    if settings.app_env=='production' and (settings.auth_mode=='demo' or not settings.officer_token):
        raise RouteError('config','Production memerlukan autentikasi dan OFFICER_TOKEN.',503)
    service=service or RouteService(settings)
    app=FastAPI(title='JAKRoute API',version='1.0.0')
    app.state.service=service
    app.add_middleware(CORSMiddleware,allow_origins=[x.strip() for x in settings.cors_origins.split(',') if x.strip()],allow_origin_regex=settings.cors_origin_regex or None,allow_credentials=False,allow_methods=['GET','POST'],allow_headers=['Authorization','Content-Type','X-Officer-Token'])
    limits=defaultdict(deque); lock=threading.Lock()

    @app.exception_handler(RouteError)
    async def domain_error(request,exc): return JSONResponse(status_code=exc.status,content={'error':exc.as_dict()})

    @app.middleware('http')
    async def size_limit(request,call_next):
        try: length=int(request.headers.get('content-length','0'))
        except ValueError: return JSONResponse(status_code=400,content={'error':{'message':'Content length tidak valid.'}})
        if length>64000: return JSONResponse(status_code=413,content={'error':{'message':'Request terlalu besar.'}})
        if request.method=='POST':
            body=await request.body()
            if len(body)>64000: return JSONResponse(status_code=413,content={'error':{'message':'Request terlalu besar.'}})
        return await call_next(request)

    def authenticate(request:Request,authorization:str|None=Header(default=None)):
        token=authorization.removeprefix('Bearer ') if authorization and authorization.startswith('Bearer ') else ''
        if settings.auth_mode=='demo': identity='demo:'+(request.client.host if request.client else 'local')
        elif settings.auth_mode=='token':
            if not settings.api_token or not secrets.compare_digest(token,settings.api_token): raise RouteError('unauthorized','Token akses tidak valid.',401)
            identity='private_operator'
        elif settings.auth_mode=='supabase':
            if not token or not settings.supabase_url or not settings.supabase_anon_key: raise RouteError('unauthorized','Login Supabase diperlukan.',401)
            try:
                with httpx.Client(timeout=10) as client:
                    r=client.get(settings.supabase_url.rstrip('/')+'/auth/v1/user',headers={'apikey':settings.supabase_anon_key,'Authorization':'Bearer '+token})
                if r.status_code!=200: raise RouteError('unauthorized','Sesi login tidak valid/berakhir.',401)
                identity=r.json()['id']
            except (httpx.HTTPError,KeyError,ValueError) as exc: raise RouteError('auth_unavailable','Layanan autentikasi tidak tersedia.',503) from exc
        else: raise RouteError('config','Mode autentikasi tidak valid.',503)
        now=time.monotonic()
        with lock:
            q=limits[identity]
            while q and q[0]<now-60: q.popleft()
            if len(q)>=60: raise RouteError('rate_limit','Terlalu banyak permintaan. Coba sebentar lagi.',429)
            q.append(now)
            if len(limits)>10000:
                stale=[key for key,value in limits.items() if not value or value[-1]<now-60]
                for key in stale: del limits[key]
        return identity

    @app.get('/health')
    def health():
        return {'status':'ok','agent_mode':settings.agent_mode,'mapid_mode':settings.mapid_mode,
                'weather_mode':settings.weather_mode,'forum_mode':settings.forum_mode,
                'station_data_mode':settings.station_data_mode,
                'crowd_user_count':service.crowd['user_count'],
                'simulated_station':service.site['simulated']}

    @app.get('/catalog')
    def catalog(identity=Depends(authenticate)): return service.catalog()

    @app.get('/crowd/snapshot')
    def crowd_snapshot(identity=Depends(authenticate)): return service.crowd_snapshot()

    @app.post('/recommend-route')
    def recommend(body:RouteRequest,identity=Depends(authenticate)):
        Preferences.parse(body.preferences)
        return service.recommend(body.model_dump())

    @app.get('/forum/summary')
    def summary(identity=Depends(authenticate)): return service.store.snapshot()

    @app.post('/forum/reports')
    def forum_report(body:ForumReport,identity=Depends(authenticate)):
        timestamp(body.observed_at)
        return service.ingest_report(body.model_dump())

    @app.post('/forum/confirm')
    def confirm(body:Confirmation,x_officer_token:str|None=Header(default=None)):
        # Never trust a role='officer' field or the words 'saya petugas' in a report.
        if not settings.officer_token or not secrets.compare_digest(x_officer_token or '',settings.officer_token):
            raise RouteError('forbidden','Konfirmasi harus melalui petugas terautentikasi.',403)
        return service.store.confirm(body.incident_id,'configured_officer',body.note,body.expected_version)

    return app
