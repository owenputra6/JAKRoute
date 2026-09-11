"""One request snapshot; enumerate real entrance handoffs; return all 3 modes."""
import copy
from .providers import OsmPoiClient,load_json,MapidClient,WeatherClient,SupabaseStationClient,create_weather_warning
from .geometry import local_to_lonlat, lonlat_to_local
from .crowd_simulation import GeoJsonCrowdSimulator,NodeCorridorCrowdSimulator
from .station_source import build_station_site
from .schemas import Preferences,MODES,LABELS
from .indoor_routing import IndoorRouter
from .forum_state import ForumStore,OllamaSummarizer,OpenAISummarizer,DemoSummarizer
from .ai_agent import RouteAgent,job_key
from .errors import RouteError

class RouteService:
    def __init__(self,settings,agent=None):
        self.settings=settings
        self.station_data=SupabaseStationClient(settings)
        self.station_snapshot=self.station_data.get_station_data()
        if settings.station_data_mode=='supabase':
            self.site=build_station_site(self.station_snapshot)
            self.crowd_simulator=NodeCorridorCrowdSimulator(
                self.site['crowd_corridors'],self.site['anchor_lonlat'],
                settings.crowd_user_count,settings.crowd_seed)
        else:
            self.site=load_json(settings.data_dir/'station_demo.json')
            ground=next(f for f in self.site['floors'] if f['id']==0)
            self.crowd_simulator=GeoJsonCrowdSimulator(
                settings.data_dir/'palmerah_crowd_areas.geojson',
                self.site['anchor_lonlat'],ground['bounds'],
                settings.crowd_user_count,settings.crowd_seed,floor=0)
        # Outdoor destinations around the station (OpenStreetMap). Local xy
        # is derived from the real lon/lat so the outdoor router can join them.
        self.outdoor_meta={'source':'not_configured','count':0}
        if settings.outdoor_poi_mode=='osm':
            pois,self.outdoor_meta=OsmPoiClient(settings).fetch(self.site['anchor_lonlat'])
            for p in pois: p['xy']=[round(v,5) for v in lonlat_to_local(p['source_lonlat'],self.site['anchor_lonlat'])]
            self.site['places']=[p for p in self.site['places'] if p.get('scope')!='outdoor' or not p['id'].startswith('osm_')]+pois
        self.crowd=self.crowd_simulator.build_snapshot()
        self.site['crowd_areas']=[{key:area[key] for key in ('id','floor','area_m2','polygon')}
                                  for area in self.crowd['areas']]
        self.router=IndoorRouter(self.site)
        self.places={p['id']:p for p in self.site['places']}
        seed=load_json(settings.data_dir/'forum_summary_seed.json') if self.site['simulated'] else None
        self.store=ForumStore(settings.db_path,seed,site_id=self.site['id'])
        self.agent=agent or RouteAgent(settings)
        self.mapid=MapidClient(settings,self.site)
        self.weather=WeatherClient(settings)
        self.summarizer=OpenAISummarizer(settings) if settings.forum_mode=='openai' else OllamaSummarizer(settings) if settings.forum_mode=='ollama' else DemoSummarizer()

    def catalog(self):
        places=[]
        for place in self.site['places']:
            enriched={**place,'lonlat':place.get('source_lonlat') or local_to_lonlat(place['xy'],self.site['anchor_lonlat'])}
            places.append(enriched)
        station_data={key:value for key,value in self.station_snapshot.items()
                      if key not in ('blocks','nodes')}
        station_data['counts']={'blocks':len(self.station_snapshot.get('blocks',[])),
                                'nodes':len(self.station_snapshot.get('nodes',[]))}
        return {**self.site,'places':places,'station_data':station_data,
                'crowd_source':self.crowd['source'],'outdoor_pois':self.outdoor_meta}

    def crowd_snapshot(self):
        return copy.deepcopy(self.crowd)

    def _plans(self,intent,prefs):
        origin,dest=intent['origin_id'],intent['destination_id']
        ao,bo=self.places[origin]['scope']=='outdoor',self.places[dest]['scope']=='outdoor'
        entrances=[p['id'] for p in self.site['places'] if p['kind']=='entrance']
        if any(self.places[x]['scope']!='indoor' for x in intent['via_indoor_ids']):
            raise RouteError('invalid_via','Via harus fasilitas indoor.')
        prefs.required_facilities=list(dict.fromkeys(prefs.required_facilities+intent['via_indoor_ids']))
        if len(prefs.required_facilities)>4: raise RouteError('via_limit','Maksimal empat fasilitas wajib.')
        if ao and bo and not prefs.required_facilities:
            return [[('outdoor',origin,dest)]]
        starts=entrances if ao else [origin]
        ends=entrances if bo else [dest]
        result=[]
        for start in starts:
            for end in ends:
                legs=[]
                if ao: legs.append(('outdoor',origin,start))
                legs.append(('indoor',start,end))
                if bo: legs.append(('outdoor',end,dest))
                result.append(legs)
        return result

    def recommend(self,request):
        context={'places':self.site['places'],'station_label':self.site['label']}
        intent=self.agent.parse_user_request(request,context)
        if intent.get('clarification') or not intent.get('origin_id') or not intent.get('destination_id'):
            fallback=('Kamu sekarang berada di mana di stasiun?' if not intent.get('origin_id') and intent.get('destination_id')
                      else 'Mau menuju ke mana?' if intent.get('origin_id') and not intent.get('destination_id') else 'Pilih asal dan tujuan.')
            return dict(status='clarification_required',question=intent.get('clarification') or fallback,routes=[],intent=intent,agent_mode=self.settings.agent_mode)
        prefs=Preferences.parse(intent['preferences'])
        plans=self._plans(intent,prefs)
        # One snapshot for the three alternatives; retry once if a forum update races calculation.
        for attempt in range(2):
            snapshot=self.store.snapshot()
            result=self._calculate(intent,prefs,plans,snapshot,self.crowd)
            if snapshot['version']==self.store.snapshot()['version']:
                return result
        raise RouteError('state_changed','Kondisi fasilitas baru saja berubah. Minta rute kembali.',409)

    def _calculate(self,intent,prefs,plans,snapshot,crowd):
        jobs=[]
        for plan in plans:
            for scope,a,b in plan:
                for mode in (MODES if scope=='indoor' else ('outdoor',)):
                    name='route_outdoor' if scope=='outdoor' else 'route_indoor_plain' if mode=='min_walk' else 'route_indoor_personalized'
                    jobs.append({'name':name,'arguments':dict(origin_id=a,destination_id=b,mode=mode)})
        jobs=list({job_key(j['name'],j['arguments']):j for j in jobs}.values())
        outdoor_cache={}
        # Compute outside lengths once for hard total-walk budgets. These are also actual tool results.
        for j in jobs:
            if j['name']=='route_outdoor':
                a,b=j['arguments']['origin_id'],j['arguments']['destination_id']
                outdoor_cache[(a,b)]=self.mapid.calculate_outdoor_route(a,b)
        budgets={}
        for plan in plans:
            outside_walk=sum(outdoor_cache[(a,b)]['walking_m'] for scope,a,b in plan if scope=='outdoor')
            for scope,a,b in plan:
                if scope=='indoor': budgets[(a,b)]=None if prefs.max_walk_m is None else prefs.max_walk_m-outside_walk
        def execute(name,args):
            a,b=args['origin_id'],args['destination_id']
            if name=='route_outdoor': return outdoor_cache[(a,b)]
            pp=copy.deepcopy(prefs)
            pp.max_walk_m=budgets[(a,b)]
            if pp.max_walk_m is not None and pp.max_walk_m<0: return {'status':'no_route','message':'Bagian outdoor telah melewati batas berjalan.'}
            try:
                return self.router.route(a,b,args['mode'],pp,users=crowd['users'],incidents=snapshot['incidents'])
            except RouteError as exc:
                if exc.code=='no_route': return {'status':'no_route','message':exc.message}
                raise
        results,trace=self.agent.execute_jobs(jobs,execute,{'intent':intent,'preferences':prefs.as_dict(),'forum_summary':snapshot})
        has_outdoor=any(scope=='outdoor' for plan in plans for scope,_,_ in plan)
        weather=self.weather.get_weather_status(self.site['anchor_lonlat']) if has_outdoor else {'source':'not_needed','is_raining':None,'simulated':False}
        routes=[]
        for mode in MODES:
            candidates=[]
            for number,plan in enumerate(plans):
                segments=[]
                for scope,a,b in plan:
                    name='route_outdoor' if scope=='outdoor' else 'route_indoor_plain' if mode=='min_walk' else 'route_indoor_personalized'
                    r=results[(name,a,b,'outdoor' if scope=='outdoor' else mode)]
                    if r.get('status')=='no_route': break
                    segments.append(r)
                if len(segments)!=len(plan): continue
                walk=sum(x['walking_m'] for x in segments)
                if prefs.max_walk_m is not None and walk>prefs.max_walk_m+0.01: continue
                duration=sum(x['duration_s'] for x in segments)
                score=walk if mode=='min_walk' else duration if mode=='fastest' else sum(x['score'] if 'score' in x else prefs.time_priority*x['duration_s']/60+prefs.walking_priority*x['walking_m']/100 for x in segments)
                candidates.append(dict(route_id=f'{mode}_{number}',mode=mode,label=LABELS[mode],status='ok',walking_m=round(walk,2),duration_s=round(duration,2),
                    distance_m=round(sum(x['distance_m'] for x in segments),2),score=round(score,5),
                    geometry={'type':'FeatureCollection','features':[f for x in segments for f in x['geometry']['features']]},
                    connectors_used=list(dict.fromkeys(c for x in segments for c in x.get('connectors_used',[]))),
                    facilities_used=list(dict.fromkeys(c for x in segments for c in x.get('facilities_used',[]))),
                    crowd_exposure=round(sum(x.get('crowd_exposure',0) for x in segments),4),
                    sources=list(dict.fromkeys(x['source'] for x in segments)),simulated=any(x['simulated'] for x in segments),valid=True))
            if not candidates:
                routes.append(dict(mode=mode,label=LABELS[mode],status='no_route',message='Tidak ada rute yang memenuhi seluruh batasan.'))
                continue
            route=min(candidates,key=lambda x:x['score'])
            reasons={'objective':{'min_walk':'Pilihan ini meminimalkan jarak berjalan di antara rute yang memenuhi batasan.',
                'fastest':'Pilihan ini meminimalkan estimasi waktu, termasuk perlambatan akibat kepadatan dan waktu akses antarlantai.',
                'best_fit':'Pilihan ini menyeimbangkan prioritas waktu, jarak berjalan, keramaian, dan preferensi akses yang diberikan.'}[mode]}
            if prefs.step_free: reasons['step_free']='Rute menggunakan akses bebas anak tangga sesuai kebutuhan pengguna.'
            if prefs.avoid_stairs: reasons['avoid_stairs']='Tangga dikeluarkan dari pilihan sesuai permintaan pengguna.'
            used_kinds={c['kind'] for c in self.site['connectors'] if c['id'] in route['connectors_used']}
            if 'elevator' in used_kinds: reasons['uses_lift']='Perpindahan lantai menggunakan lift.'
            if 'escalator' in used_kinds: reasons['uses_escalator']='Perpindahan lantai menggunakan eskalator.'
            if 'stairs' in used_kinds: reasons['uses_stairs']='Perpindahan lantai menggunakan tangga.'
            if 'stairs_link' in route['connectors_used']: reasons['uses_stairs']='Perpindahan lantai menggunakan tangga.'
            if 'escalator_link' in route['connectors_used']: reasons['uses_escalator']='Perpindahan lantai menggunakan eskalator.'
            if any(i['effect'] in ('unavailable','blocked') or i['routing_code']==-1 for i in snapshot['incidents']) and 'indoor_python_grid' in route['sources']: reasons['forum']='Akses yang dilaporkan tidak dapat digunakan tetap dikecualikan sampai ada konfirmasi petugas.'
            warnings=create_weather_warning(weather,has_outdoor)
            if route['simulated']: warnings.append('Hasil memakai denah/data simulasi; bukan petunjuk navigasi stasiun sebenarnya.')
            elif self.site.get('routing_geometry_derived'):
                warnings.append('Block dan titik berasal dari Supabase; batas walkable masih geometri turunan dan perlu divalidasi di stasiun.')
            if not any(scope=='indoor' for plan in plans for scope,_,_ in plan):
                warnings.append('Perjalanan ini seluruhnya outdoor. Tiga kriteria belum dioptimalkan oleh mesin indoor; hasil mengikuti kandidat provider yang tersedia.')
            route.update(reasons=reasons,warnings=warnings,explanation=' '.join(reasons.values()))
            routes.append(route)
        valid=[r for r in routes if r['status']=='ok']
        if not valid:
            return dict(status='no_route',routes=routes,intent=intent,forum_summary=snapshot,agent_mode=self.settings.agent_mode,tool_trace=trace)
        selected=next((r for r in valid if r['mode']==intent['focus_mode']),valid[0])
        selected['explanation']=self.agent.explain(selected)
        # Same physical route may be optimal for multiple objectives; do not invent alternatives.
        for r in valid:
            sig=r['geometry']['features']
            r['same_geometry_as']=[x['mode'] for x in valid if x is not r and x['geometry']['features']==sig]
            r['insight']=self._route_insight(r,prefs,ai_selected=r is selected)
        return dict(status='ok',routes=routes,selected_route_id=selected['route_id'],intent=intent,preferences=prefs.as_dict(),
            forum_summary=snapshot,weather=weather,crowd_observed_at=crowd['observed_at'],crowd_simulated=crowd['simulated'],
            crowd_snapshot_id=crowd['snapshot_id'],crowd_user_count=crowd['user_count'],
            ai_insight=selected['insight'],agent_mode=self.settings.agent_mode,tool_trace=trace,station_id=self.site['id'])

    def _route_insight(self,route,prefs,ai_selected=False):
        personalized=[]
        if prefs.step_free: personalized.append('akses bebas anak tangga')
        elif prefs.avoid_stairs: personalized.append('menghindari tangga')
        if prefs.preferred_access!='any': personalized.append('preferensi '+prefs.preferred_access)
        if prefs.max_walk_m is not None: personalized.append(f'batas berjalan {prefs.max_walk_m:g} m')
        if (prefs.time_priority,prefs.walking_priority,prefs.crowd_priority)!=(1.0,1.0,1.0):
            personalized.append(f'prioritas waktu/jalan/crowd {prefs.time_priority:g}/{prefs.walking_priority:g}/{prefs.crowd_priority:g}')
        return {
            'headline':route['label'],
            'summary':route['explanation'],
            'personalization':personalized,
            'facts':[
                {'label':'Jarak berjalan','value':f"{route['walking_m']:.0f} m"},
                {'label':'Estimasi waktu','value':f"{route['duration_s']/60:.1f} menit"},
                {'label':'Paparan crowd berbobot','value':f"{route['crowd_exposure']:.2f}"},
            ],
            'generator':'openai_reason_selection' if ai_selected and self.settings.agent_mode=='openai'
                        else 'deterministic_demo' if self.settings.agent_mode=='demo'
                        else 'backend_evidence',
        }

    def ingest_report(self,report):
        known=set(self.places)|{x['id'] for x in self.site['connectors']}|{x['id'] for x in self.site['crowd_areas']}
        if report['resource_id'] not in known: raise RouteError('unknown_resource','Lokasi laporan tidak ada dalam katalog.')
        if self.settings.forum_mode=='demo':
            fixtures=load_json(self.settings.data_dir/'forum_reports.json')
            if report not in fixtures: raise RouteError('demo_report','Mode demo menerima laporan fixture persis. Aktifkan FORUM_MODE=openai untuk laporan baru.')
        previous=self.store.snapshot()
        extraction=self.summarizer.summarize(report,previous)
        changed=self.store.update(report,extraction)
        return dict(changed=changed,extraction=extraction,forum_summary=self.store.snapshot(),processor=self.settings.forum_mode)
