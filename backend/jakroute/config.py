from dataclasses import dataclass
from pathlib import Path
import os
from dotenv import load_dotenv
from .errors import RouteError

ROOT=Path(__file__).resolve().parents[1]
load_dotenv(ROOT/'.env',override=False)

@dataclass
class Settings:
    data_dir: Path=ROOT/'data'
    db_path: str=str(ROOT/'runtime'/'forum.sqlite3')
    agent_mode: str='demo'
    mapid_mode: str='demo'
    outdoor_poi_mode: str='demo'
    outdoor_poi_radius_m: int=350
    weather_mode: str='demo'
    forum_mode: str='demo'
    openai_api_key: str=''
    openai_model: str=''
    mapid_api_key: str=''
    google_weather_api_key: str=''
    ollama_base_url: str='http://127.0.0.1:11434'
    # Gemma 4 E4B is the default local forum summarizer. Use a smaller tag if
    # the development machine cannot keep the model in memory.
    ollama_model: str='gemma4:e4b'
    officer_token: str=''
    auth_mode: str='demo'
    api_token: str=''
    supabase_url: str=''
    supabase_anon_key: str=''
    station_data_mode: str='demo'
    supabase_blocks_table: str='station_blocks'
    supabase_nodes_table: str='station_nodes'
    supabase_station_id: str='palmerah'
    crowd_user_count: int=100
    crowd_seed: int=20260908
    app_env: str='development'
    cors_origins: str='http://localhost:3000,http://localhost:8080'
    cors_origin_regex: str=''

    @classmethod
    def from_env(cls):
        kwargs={}
        for name in cls.__dataclass_fields__:
            key=name.upper()
            if key in os.environ: kwargs[name]=os.environ[key]
        if 'data_dir' in kwargs: kwargs['data_dir']=Path(kwargs['data_dir'])
        for name in ('crowd_user_count','crowd_seed','outdoor_poi_radius_m'):
            if name in kwargs:
                try: kwargs[name]=int(kwargs[name])
                except ValueError as exc: raise RouteError('config',f'{name} harus integer.',503) from exc
        result=cls(**kwargs)
        for name,allowed in [('agent_mode',('demo','openai')),('mapid_mode',('demo','live','osrm')),('weather_mode',('demo','google')),('forum_mode',('demo','openai','ollama')),('auth_mode',('demo','token','supabase')),('station_data_mode',('demo','supabase')),('outdoor_poi_mode',('demo','osm'))]:
            if getattr(result,name) not in allowed: raise RouteError('config',f'{name} tidak valid.',503)
        if not 9<=result.crowd_user_count<=1000: raise RouteError('config','crowd_user_count harus 9–1000.',503)
        if result.app_env=='production' and (result.auth_mode=='demo' or not result.officer_token):
            raise RouteError('config','Production memerlukan autentikasi dan OFFICER_TOKEN.',503)
        return result
