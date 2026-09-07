"""Actual HTTP integrations + explicit, never silent, simulated providers."""
import json
import math
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

    def _result(self,origin,destination,coords,metres,seconds,source,simulated):
        return dict(origin=origin,destination=destination,walking_m=metres,distance_m=metres,duration_s=seconds,source=source,simulated=simulated,
          geometry={'type':'FeatureCollection','features':[{'type':'Feature','geometry':{'type':'LineString','coordinates':coords},'properties':{'scope':'outdoor','floor':None,'to_floor':None,'access':'walk'}}]})

class WeatherClient:
    def __init__(self,settings): self.settings=settings

    def get_weather_status(self,lonlat):
        if self.settings.weather_mode=='demo': return load_json(self.settings.data_dir/'weather_dummy.json')
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
