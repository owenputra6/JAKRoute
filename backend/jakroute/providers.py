"""Actual HTTP integrations + explicit, never silent, simulated providers."""
import json
import math
import re
from datetime import datetime,timezone
import httpx
from .geometry import local_to_lonlat, distance
from .errors import RouteError

def load_json(path):
    return json.loads(path.read_text(encoding='utf-8'))

def json_http(method,url,**kwargs):
    try:
        with httpx.Client(timeout=25,follow_redirects=False) as client:
            r=client.request(method,url,**kwargs)
            r.raise_for_status()
            return r.json()
    except (httpx.HTTPError,ValueError) as exc:
        # Do not echo request URLs, response body or credentials in public errors.
        raise RouteError('provider_error','Provider eksternal gagal/timeout. Coba lagi.',502) from exc

def at_path(value,path):
    for key in path.split('.'):
        value=value[int(key)] if isinstance(value,list) else value[key]
    return value

def template(value,values):
    if isinstance(value,dict): return {k:template(v,values) for k,v in value.items()}
    if isinstance(value,list): return [template(v,values) for v in value]
    if isinstance(value,str):
        if value.startswith('${') and value.endswith('}') and value[2:-1] in values: return values[value[2:-1]]
        for k,v in values.items(): value=value.replace('${'+k+'}',str(v))
    return value

class MapidClient:
    def __init__(self,settings,site): self.settings,self.site=settings,site

    def calculate_outdoor_route(self,origin,destination):
        places={x['id']:x for x in self.site['places']}
        a,b=places[origin],places[destination]
        anchor=self.site['anchor_lonlat']
        start=local_to_lonlat(a['xy'],anchor); end=local_to_lonlat(b['xy'],anchor)
        if self.settings.mapid_mode=='osrm':
            return self._osrm_foot(origin,destination,a,b,start,end,anchor)
        if self.settings.mapid_mode=='demo':
            # Synthetic right-angle sidewalk outside the building. Never called MAPID output.
            points=[a['xy'],b['xy']]
            # Keep a cross-station outdoor demo outside its rectangular footprint.
            if a['xy'][0]<0 and b['xy'][0]>60 or b['xy'][0]<0 and a['xy'][0]>60:
                points=[a['xy'],[a['xy'][0],-8],[b['xy'][0],-8],b['xy']]
            coords=[local_to_lonlat(p,anchor) for p in points]
            metres=sum(distance(p,q) for p,q in zip(points,points[1:]))
            return self._result(origin,destination,coords,metres,metres/1.2,'simulated_outdoor',True)
        contract=load_json(self.settings.data_dir/'mapid_contract.json')
        if not contract.get('configured') or not contract.get('url'):
            raise RouteError('mapid_not_configured','Isi endpoint dan kontrak routing MAPID yang terverifikasi di mapid_contract.json.',503)
        if not contract['url'].startswith('https://'): raise RouteError('config','Endpoint MAPID live harus HTTPS.',503)
        if not self.settings.mapid_api_key: raise RouteError('config','MAPID_API_KEY belum diisi.',503)
        values=dict(api_key=self.settings.mapid_api_key,origin_lon=start[0],origin_lat=start[1],destination_lon=end[0],destination_lat=end[1])
        kwargs=dict(headers=template(contract.get('headers',{}),values),params=template(contract.get('query',{}),values))
        if contract['method'].upper()=='POST': kwargs['json']=template(contract.get('body',{}),values)
        payload=json_http(contract['method'],template(contract['url'],values),**kwargs)
        paths=contract['response']
        try:
            coords=at_path(payload,paths['coordinates_path'])
            metres=float(at_path(payload,paths['distance_path']))*paths.get('distance_multiplier',1)
            duration=float(at_path(payload,paths['duration_path']))*paths.get('duration_multiplier',1)
            if not isinstance(coords,list) or len(coords)<2: raise ValueError()
            if any(len(p)!=2 or not all(isinstance(x,(float,int)) and math.isfinite(x) for x in p) or not -180<=p[0]<=180 or not -90<=p[1]<=90 for p in coords): raise ValueError()
            if not all(math.isfinite(x) and x>=0 for x in (metres,duration)): raise ValueError()
            # A provider snapped >15m from an entrance cannot be silently joined to indoor.
            from .geometry import lonlat_to_local
            if distance(lonlat_to_local(coords[0],anchor),a['xy'])>15 or distance(lonlat_to_local(coords[-1],anchor),b['xy'])>15:
                raise RouteError('handoff_gap','Endpoint outdoor lebih dari 15 m dari titik penghubung indoor. Perbaiki titik akses.',422)
        except (KeyError,TypeError,ValueError,IndexError) as exc:
            raise RouteError('mapid_schema','Respons MAPID tidak sesuai kontrak yang dikonfigurasi.',502) from exc
        result=self._result(origin,destination,coords,metres,duration,'mapid_live',False)
        result['handoff_offsets_m']=[distance(lonlat_to_local(coords[0],anchor),a['xy']),distance(lonlat_to_local(coords[-1],anchor),b['xy'])]
        return result

    # Free OpenStreetMap foot routing (FOSSGIS OSRM instance). Used until a
    # MAPID routing contract is available; MAPID Maps routing is a paid,
    # vehicle-oriented product with no public walking endpoint.
    OSRM_FOOT='https://routing.openstreetmap.de/routed-foot/route/v1/foot/'

    def _osrm_foot(self,origin,destination,a,b,start,end,anchor):
        url=f"{self.OSRM_FOOT}{start[0]:.6f},{start[1]:.6f};{end[0]:.6f},{end[1]:.6f}"
        payload=json_http('GET',url,params={'overview':'full','geometries':'geojson','steps':'false'},
                          headers={'User-Agent':'JAKRoute/1.0 (MAPID WebGIS Competition 2026)'})
        try:
            route=payload['routes'][0]
            coords=list(route['geometry']['coordinates']); metres=float(route['distance']); seconds=float(route['duration'])
            if len(coords)<2: raise ValueError()
        except (KeyError,IndexError,TypeError,ValueError) as exc:
            raise RouteError('osrm_schema','Respons OSRM tidak dikenali.',502) from exc
        from .geometry import lonlat_to_local
        # OSRM snaps to the nearest footway; walk straight from the door to
        # that point (and from the last point to the POI) so the line joins.
        gap_start=distance(lonlat_to_local(coords[0],anchor),a['xy']); gap_end=distance(lonlat_to_local(coords[-1],anchor),b['xy'])
        if gap_start>1: coords.insert(0,list(start)); metres+=gap_start; seconds+=gap_start/1.2
        if gap_end>1: coords.append(list(end)); metres+=gap_end; seconds+=gap_end/1.2
        result=self._result(origin,destination,coords,round(metres,2),round(seconds,2),'osrm_foot_openstreetmap',False)
        result['handoff_offsets_m']=[round(gap_start,2),round(gap_end,2)]
        return result

    def _result(self,origin,destination,coords,metres,seconds,source,simulated):
        return dict(origin=origin,destination=destination,walking_m=metres,distance_m=metres,duration_s=seconds,source=source,simulated=simulated,
          geometry={'type':'FeatureCollection','features':[{'type':'Feature','geometry':{'type':'LineString','coordinates':coords},'properties':{'scope':'outdoor','floor':None,'to_floor':None,'access':'walk'}}]})

class WeatherClient:
    def __init__(self,settings): self.settings=settings

    def get_weather_status(self,lonlat):
        if self.settings.weather_mode=='demo':
            return {**load_json(self.settings.data_dir/'weather_dummy.json'),'location_lonlat':lonlat}
        if not self.settings.google_weather_api_key:
            return dict(source='unavailable',simulated=False,is_raining=None,condition='UNKNOWN',observed_at=None)
        try:
            data=json_http('GET','https://weather.googleapis.com/v1/currentConditions:lookup',params={'key':self.settings.google_weather_api_key,'location.latitude':lonlat[1],'location.longitude':lonlat[0]})
            condition=data.get('weatherCondition',{}).get('type','UNKNOWN')
            rain=any(token in condition for token in ('RAIN','DRIZZLE','THUNDERSTORM','THUNDERSHOWER')) or condition=='SCATTERED_SHOWERS'
            if condition in ('UNKNOWN','TYPE_UNSPECIFIED','CHANCE_OF_SHOWERS'): rain=None
            return dict(source='google_weather',simulated=False,is_raining=rain,condition=condition,observed_at=data.get('currentTime'),location_lonlat=lonlat)
        except RouteError:
            return dict(source='unavailable',simulated=False,is_raining=None,condition='UNKNOWN',observed_at=None)

def create_weather_warning(weather,has_outdoor):
    if not has_outdoor: return []
    if weather.get('is_raining') is True:
        return ['Hujan terdeteksi. Bagian rute luar ruangan berpotensi terkena hujan.']
    if weather.get('is_raining') is None:
        return ['Data cuaca belum tersedia untuk bagian rute luar ruangan.']
    return []


class SupabaseStationClient:
    """Read the two routing-source tables through Supabase REST."""
    block_fields='id,station_id,floor,source_no,name,block_type,is_obstacle,geom,metadata'
    node_fields='id,station_id,floor,source_no,name,node_type,linked_block_id,is_routable,geom,crowd_zone_id,crowd_sequence,crowd_width_m,metadata'

    def __init__(self,settings): self.settings=settings

    def _fetch(self,table,fields):
        if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*',table):
            raise RouteError('config','Nama tabel Supabase tidak valid.',503)
        rows=json_http('GET',self.settings.supabase_url.rstrip('/')+f'/rest/v1/{table}',
            headers={'apikey':self.settings.supabase_anon_key,
                     'Authorization':'Bearer '+self.settings.supabase_anon_key},
            params={'select':fields,'station_id':'eq.'+self.settings.supabase_station_id,
                    'order':'floor.asc,source_no.asc','limit':'2000'})
        if not isinstance(rows,list):
            raise RouteError('supabase_schema',f'Respons {table} harus berupa array.',502)
        return rows

    def get_station_data(self):
        if self.settings.station_data_mode=='demo':
            return {'source':'not_configured','simulated':False,'blocks':[],'nodes':[]}
        if not self.settings.supabase_url or not self.settings.supabase_anon_key:
            raise RouteError('supabase_not_configured','Isi SUPABASE_URL dan SUPABASE_ANON_KEY untuk STATION_DATA_MODE=supabase.',503)
        blocks=self._fetch(self.settings.supabase_blocks_table,self.block_fields)
        nodes=self._fetch(self.settings.supabase_nodes_table,self.node_fields)
        if not blocks or not nodes or any(not isinstance(row,dict) for row in blocks+nodes):
            raise RouteError('supabase_schema','station_blocks dan station_nodes harus berisi object.',502)
        return {'source':'supabase_rest','simulated':False,
            'station_id':self.settings.supabase_station_id,
            'tables':{'blocks':self.settings.supabase_blocks_table,
                      'nodes':self.settings.supabase_nodes_table},
            'blocks':blocks,'nodes':nodes}


class OsmPoiClient:
    """Nearby outdoor destinations from OpenStreetMap via Overpass (free).

    Only named features within `radius_m` of the station anchor. Cached to
    data_dir/outdoor_pois_cache.json so a slow Overpass does not block boot;
    the cache is reused when the live query fails.
    """
    OVERPASS=('https://overpass-api.de/api/interpreter','https://overpass.kumi.systems/api/interpreter')
    KINDS={'restaurant':'food','cafe':'food','fast_food':'food','food_court':'food',
           'bus_stop':'bus_stop','bus_station':'bus_stop','convenience':'minimarket','supermarket':'minimarket','pharmacy':'pharmacy'}

    def __init__(self,settings): self.settings=settings

    def fetch(self,anchor):
        cache=self.settings.data_dir/'outdoor_pois_cache.json'
        lon,lat=anchor; r=self.settings.outdoor_poi_radius_m
        q=(f'[out:json][timeout:20];('
           f'nwr["amenity"~"^(restaurant|cafe|fast_food|food_court|bus_station|pharmacy)$"](around:{r},{lat},{lon});'
           f'nwr["highway"="bus_stop"](around:{r},{lat},{lon});'
           f'nwr["shop"~"^(convenience|supermarket)$"](around:{r},{lat},{lon}););out center tags;')
        try:
            payload=None
            for host in self.OVERPASS:
                try:
                    payload=json_http('POST',host,data={'data':q},headers={'User-Agent':'JAKRoute/1.0 (MAPID WebGIS Competition 2026)'}); break
                except RouteError: continue
            if payload is None: raise RouteError('provider_error','Overpass tidak tersedia.',502)
            elements=payload.get('elements',[])
            fetched_at=datetime.now(timezone.utc).isoformat()
            try: cache.write_text(json.dumps({'fetched_at':fetched_at,'elements':elements},ensure_ascii=False),encoding='utf-8')
            except OSError: pass
            source='overpass_live'
        except RouteError:
            if not cache.exists(): return [],{'source':'unavailable','fetched_at':None}
            saved=load_json(cache); elements=saved.get('elements',[]); fetched_at=saved.get('fetched_at'); source='overpass_cache'
        places=[]
        for e in elements:
            tags=e.get('tags') or {}
            name=tags.get('name')
            if not name: continue
            raw=tags.get('amenity') or tags.get('highway') or tags.get('shop')
            kind=self.KINDS.get(raw)
            if not kind: continue
            lon_,lat_=(e.get('lon'),e.get('lat')) if e.get('type')=='node' else ((e.get('center') or {}).get('lon'),(e.get('center') or {}).get('lat'))
            if lon_ is None or lat_ is None: continue
            places.append({'id':f"osm_{e['type']}_{e['id']}",'label':name,'kind':kind,'scope':'outdoor','floor':None,
                           'source_lonlat':[float(lon_),float(lat_)],'osm_tag':f'{"amenity" if raw in ("restaurant","cafe","fast_food","food_court","bus_station","pharmacy") else "highway" if raw=="bus_stop" else "shop"}={raw}',
                           'source':'openstreetmap','node_type':'outdoor_poi'})
        places.sort(key=lambda p:p['label'])
        return places,{'source':source,'fetched_at':fetched_at,'radius_m':r,'count':len(places)}
