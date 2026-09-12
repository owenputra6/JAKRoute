"""Deterministic weighted crowd points sampled from a GeoJSON area source.

Source coordinates are preserved for map display. A documented rigid rotation
and scale places the same points inside the prototype routing floor so the
current indoor graph can consume them without pretending that the GeoJSON is a
complete routing network.
"""
from datetime import datetime, timezone
import math
import random
import re

from .crowd import calculate_area_crowd_weight
from .errors import RouteError
from .geometry import in_polygon, lonlat_to_local
from .providers import load_json
from .geometry import local_to_lonlat


def _slug(value):
    text=re.sub(r'[^a-z0-9]+','_',str(value).strip().lower()).strip('_')
    return text or 'area'


def _largest_remainder(areas,count):
    """Allocate all users by source area while keeping one per feature."""
    if count<len(areas):
        raise RouteError('crowd_count','Jumlah user crowd harus minimal sebanyak area GeoJSON.',503)
    result={area['id']:1 for area in areas}
    remaining=count-len(areas)
    total=sum(area['area_m2'] for area in areas)
    raw={area['id']:remaining*area['area_m2']/total for area in areas}
    for area in areas: result[area['id']]+=math.floor(raw[area['id']])
    left=count-sum(result.values())
    ranked=sorted(areas,key=lambda area:(raw[area['id']]-math.floor(raw[area['id']]),area['id']),reverse=True)
    for area in ranked[:left]: result[area['id']]+=1
    return result


class GeoJsonCrowdSimulator:
    def __init__(self,path,anchor_lonlat,target_bounds,user_count=100,seed=20260908,floor=0):
        self.path=path
        self.anchor_lonlat=anchor_lonlat
        self.target_bounds=[float(x) for x in target_bounds]
        self.user_count=int(user_count)
        self.seed=int(seed)
        self.floor=int(floor)
        self.geojson=load_json(path)
        self._validate_source()

    def _validate_source(self):
        if self.geojson.get('type')!='FeatureCollection' or not self.geojson.get('features'):
            raise RouteError('crowd_geojson','Crowd GeoJSON harus FeatureCollection yang tidak kosong.',503)
        seen=set()
        for feature in self.geojson['features']:
            if feature.get('geometry',{}).get('type')!='Polygon':
                raise RouteError('crowd_geojson','Prototype crowd hanya menerima Polygon.',503)
            props=feature.get('properties') or {}
            area_id=_slug(props.get('id_tool'))
            if area_id in seen: raise RouteError('crowd_geojson','ID area GeoJSON harus unik.',503)
            seen.add(area_id)
            area=props.get('area_meter_square')
            if isinstance(area,bool) or not isinstance(area,(int,float)) or not math.isfinite(area) or area<=0:
                raise RouteError('crowd_geojson','Setiap area memerlukan area_meter_square positif.',503)
            rings=feature['geometry'].get('coordinates')
            if not isinstance(rings,list) or not rings or len(rings[0])<4:
                raise RouteError('crowd_geojson','Ring polygon crowd tidak valid.',503)

    def _source_local_rings(self,feature):
        return [[lonlat_to_local(point,self.anchor_lonlat) for point in ring]
                for ring in feature['geometry']['coordinates']]

    def _transform(self,point,source_extent):
        # Rotate the source 90 degrees to match the horizontal prototype floor,
        # then use one scale factor so shapes are not stretched.
        x,y=point
        rx,ry=y,-x
        min_rx,min_ry,max_rx,max_ry=source_extent
        tx0,ty0,tx1,ty1=self.target_bounds
        scale=min((tx1-tx0)/(max_rx-min_rx),(ty1-ty0)/(max_ry-min_ry))
        used_w=(max_rx-min_rx)*scale;used_h=(max_ry-min_ry)*scale
        ox=tx0+((tx1-tx0)-used_w)/2-min_rx*scale
        oy=ty0+((ty1-ty0)-used_h)/2-min_ry*scale
        return [ox+rx*scale,oy+ry*scale]

    @staticmethod
    def _sample_lonlat(rings,rng):
        outer=rings[0]
        xmin=min(p[0] for p in outer);xmax=max(p[0] for p in outer)
        ymin=min(p[1] for p in outer);ymax=max(p[1] for p in outer)
        for _ in range(10000):
            point=[rng.uniform(xmin,xmax),rng.uniform(ymin,ymax)]
            if in_polygon(point,rings): return point
        raise RouteError('crowd_geojson','Gagal mengambil titik valid di dalam polygon crowd.',503)

    def build_snapshot(self,observed_at=None):
        features=self.geojson['features']
        source_local=[self._source_local_rings(feature) for feature in features]
        rotated=[(p[1],-p[0]) for rings in source_local for ring in rings for p in ring]
        extent=[min(p[0] for p in rotated),min(p[1] for p in rotated),
                max(p[0] for p in rotated),max(p[1] for p in rotated)]
        areas=[]
        for feature,rings in zip(features,source_local):
            props=feature['properties'];area_id='geo_'+_slug(props['id_tool'])
            areas.append({
                'id':area_id,'label':str(props['id_tool']),'floor':self.floor,
                'area_m2':float(props['area_meter_square']),
                'polygon':[[self._transform(point,extent) for point in ring] for ring in rings],
                'geojson_geometry':feature['geometry'],
            })
        counts=_largest_remainder(areas,self.user_count)
        rng=random.Random(self.seed)
        users=[]
        feature_by_id={'geo_'+_slug(f['properties']['id_tool']):f for f in features}
        for area in areas:
            source_rings=feature_by_id[area['id']]['geometry']['coordinates']
            for _ in range(counts[area['id']]):
                lonlat=self._sample_lonlat(source_rings,rng)
                local_source=lonlat_to_local(lonlat,self.anchor_lonlat)
                users.append({
                    'id':f'crowd_{len(users)+1:03d}',
                    'area_id':area['id'],'floor':self.floor,
                    'weight':round(rng.uniform(0.65,1.55),3),
                    'lonlat':[round(lonlat[0],10),round(lonlat[1],10)],
                    'xy':[round(v,4) for v in self._transform(local_source,extent)],
                })
        layer=calculate_area_crowd_weight(areas,users)
        public_areas=[]
        for area in areas:
            stats=layer[area['id']]
            public_areas.append({**area,'user_count':counts[area['id']],
                'weighted_users':round(stats['weighted_users'],4),
                'density':round(stats['density'],6)})
        timestamp=observed_at or datetime.now(timezone.utc).isoformat().replace('+00:00','Z')
        return {
            'snapshot_id':f'geojson-{self.seed}-{self.user_count}',
            'simulated':True,'observed_at':timestamp,'user_count':len(users),
            'total_weight':round(sum(user['weight'] for user in users),4),
            'users':users,'areas':public_areas,
            'source':{
                'kind':'geojson_area_sampling','file':self.path.name,
                'feature_count':len(features),
                'source_fields':['id_tool','area_meter_square','area_hectare'],
                'floor_source':'GeoJSON tidak memiliki atribut lantai; prototype menetapkan floor 0.',
            },
            'routing_transform':{
                'purpose':'Memetakan titik crowd ke geometri routing demo, bukan mengganti network routing.',
                'rotation_degrees':90,'target_bounds':self.target_bounds,
            },
        }


class NodeCorridorCrowdSimulator:
    """Create weighted dummy users inside corridors defined by station nodes."""

    def __init__(self,corridors,anchor_lonlat,user_count=100,seed=20260908):
        self.corridors=corridors
        self.anchor_lonlat=anchor_lonlat
        self.user_count=int(user_count)
        self.seed=int(seed)
        if not corridors:
            raise RouteError('crowd_corridor','Crowd corridor belum tersedia.',503)

    @staticmethod
    def _area(corridor):
        a,b=corridor['points']
        length=math.hypot(b[0]-a[0],b[1]-a[1])
        return length*float(corridor['width_m'])

    @staticmethod
    def _ring(corridor):
        a,b=corridor['points'];width=float(corridor['width_m'])
        dx,dy=b[0]-a[0],b[1]-a[1]
        length=math.hypot(dx,dy)
        if length<=0 or width<=0:
            raise RouteError('crowd_corridor','Panjang dan lebar crowd corridor harus positif.',503)
        nx,ny=-dy/length*width/2,dx/length*width/2
        return [[a[0]+nx,a[1]+ny],[b[0]+nx,b[1]+ny],
                [b[0]-nx,b[1]-ny],[a[0]-nx,a[1]-ny],[a[0]+nx,a[1]+ny]]

    def build_snapshot(self,observed_at=None):
        areas=[]
        for corridor in self.corridors:
            ring=self._ring(corridor)
            areas.append({
                'id':corridor['id'],'label':corridor.get('label',corridor['id']),
                'floor':int(corridor['floor']),'area_m2':self._area(corridor),
                'polygon':[ring],
                'geojson_geometry':{
                    'type':'Polygon',
                    'coordinates':[[local_to_lonlat(point,self.anchor_lonlat) for point in ring]],
                },
                'width_m':float(corridor['width_m']),
            })
        counts=_largest_remainder(areas,self.user_count)
        rng=random.Random(self.seed)
        users=[]
        by_id={corridor['id']:corridor for corridor in self.corridors}
        for area in areas:
            corridor=by_id[area['id']];a,b=corridor['points']
            dx,dy=b[0]-a[0],b[1]-a[1]
            length=math.hypot(dx,dy);nx,ny=-dy/length,dx/length
            for _ in range(counts[area['id']]):
                along=rng.random()
                across=rng.uniform(-float(corridor['width_m'])/2,float(corridor['width_m'])/2)
                xy=[a[0]+along*dx+across*nx,a[1]+along*dy+across*ny]
                users.append({
                    'id':f'crowd_{len(users)+1:03d}','area_id':area['id'],
                    'floor':area['floor'],'weight':round(rng.uniform(.75,1.75),3),
                    'lonlat':[round(value,10) for value in local_to_lonlat(xy,self.anchor_lonlat)],
                    'xy':[round(value,5) for value in xy],
                })
        layer=calculate_area_crowd_weight(areas,users)
        public_areas=[]
        for area in areas:
            stats=layer[area['id']]
            public_areas.append({**area,'user_count':counts[area['id']],
                'weighted_users':round(stats['weighted_users'],4),
                'density':round(stats['density'],6)})
        timestamp=observed_at or datetime.now(timezone.utc).isoformat().replace('+00:00','Z')
        return {
            'snapshot_id':f'node-corridor-{self.seed}-{self.user_count}',
            'simulated':True,'observed_at':timestamp,'user_count':len(users),
            'total_weight':round(sum(user['weight'] for user in users),4),
            'users':users,'areas':public_areas,
            'source':{
                'kind':'station_node_corridor_sampling',
                'tables':['station_blocks','station_nodes'],
                'corridor_count':len(areas),
                'description':'100 user dummy berbobot di koridor yang dibentuk titik 19-20.',
            },
            'routing_transform':{
                'purpose':'Tidak ada transformasi: crowd dan routing memakai koordinat station_nodes yang sama.',
                'rotation_degrees':0,
            },
        }


class HotspotCrowdSimulator:
    """Weighted dummy users at the places where a station actually queues:
    the tap gates, escalator and stair landings, entrances, plus the surveyed
    crowd corridor. Areas are circles around real station_nodes (merged when
    they touch). Still a labelled simulation — no live sensor — but it makes
    the crowd-aware modes (fastest / best_fit) diverge from min_walk where a
    crowded landing has a less crowded alternative.
    """
    RADIUS_M={'ticket_gate':4.0,'escalator':3.5,'stairs':3.5,'entrance':3.0,'elevator':2.5}
    # Relative crowd share per kind; individual areas get a seeded jitter so
    # two escalators are not equally busy.
    SHARE={'ticket_gate':3.0,'escalator':2.0,'stairs':1.2,'entrance':1.0,'elevator':0.6,'corridor':1.0}

    def __init__(self,site,user_count=100,seed=20260908):
        self.site=site
        self.user_count=int(user_count)
        self.seed=int(seed)

    def _areas(self):
        from shapely.geometry import Point,Polygon
        from shapely.ops import unary_union
        rng=random.Random(self.seed)
        areas=[]
        for floor in sorted({p['floor'] for p in self.site['places'] if p.get('scope')=='indoor'}):
            groups={}
            for p in self.site['places']:
                if p.get('scope')!='indoor' or p['floor']!=floor or p['kind'] not in self.RADIUS_M: continue
                groups.setdefault(p['kind'],[]).append(p)
            for kind,places in groups.items():
                merged=unary_union([Point(p['xy']).buffer(self.RADIUS_M[kind],resolution=8) for p in places])
                polys=list(merged.geoms) if hasattr(merged,'geoms') else [merged]
                for poly in polys:
                    labels=[p['label'] for p in places if poly.covers(Point(p['xy']))]
                    ring=[[round(x,4),round(y,4)] for x,y in poly.exterior.coords]
                    areas.append({'id':f"hot_{floor}_{_slug('_'.join(labels)[:60])}",'label':' / '.join(labels),
                                  'floor':int(floor),'kind':kind,'area_m2':round(poly.area,3),'polygon':[ring],
                                  'share':self.SHARE[kind]*rng.uniform(0.4,1.6)})
        for corridor in self.site.get('crowd_corridors',[]):
            ring=NodeCorridorCrowdSimulator._ring(corridor)
            areas.append({'id':corridor['id'],'label':corridor.get('label',corridor['id']),'floor':int(corridor['floor']),
                          'kind':'corridor','area_m2':NodeCorridorCrowdSimulator._area(corridor),'polygon':[ring],
                          'share':self.SHARE['corridor']})
        # Areas must be disjoint (each user belongs to exactly one). Trim any
        # overlap between kinds in favour of the earlier area.
        from shapely.geometry import shape
        kept=[]
        for area in areas:
            poly=Polygon(area['polygon'][0])
            for other in kept:
                if other['floor']!=area['floor']: continue
                poly=poly.difference(Polygon(other['polygon'][0]))
            if poly.is_empty or poly.area<1: continue
            if poly.geom_type!='Polygon': poly=max(poly.geoms,key=lambda g:g.area)
            area['polygon']=[[[round(x,4),round(y,4)] for x,y in poly.exterior.coords]]
            area['area_m2']=round(poly.area,3)
            kept.append(area)
        return kept

    def build_snapshot(self,observed_at=None):
        from shapely.geometry import Point,Polygon
        areas=self._areas()
        if not areas: raise RouteError('crowd_corridor','Tidak ada area crowd yang dapat disimulasikan.',503)
        total_share=sum(a['share'] for a in areas)
        counts={a['id']:1 for a in areas}
        remaining=self.user_count-len(areas)
        if remaining<0: raise RouteError('crowd_count','Jumlah user crowd terlalu kecil untuk jumlah area.',503)
        raw={a['id']:remaining*a['share']/total_share for a in areas}
        for a in areas: counts[a['id']]+=math.floor(raw[a['id']])
        left=self.user_count-sum(counts.values())
        for a in sorted(areas,key=lambda a:(raw[a['id']]-math.floor(raw[a['id']]),a['id']),reverse=True)[:left]: counts[a['id']]+=1
        rng=random.Random(self.seed+1)
        users=[]
        for area in areas:
            poly=Polygon(area['polygon'][0]); minx,miny,maxx,maxy=poly.bounds
            made=0
            while made<counts[area['id']]:
                xy=[rng.uniform(minx,maxx),rng.uniform(miny,maxy)]
                if not poly.contains(Point(xy)): continue
                users.append({'id':f'crowd_{len(users)+1:03d}','area_id':area['id'],'floor':area['floor'],
                              'weight':round(rng.uniform(.75,1.75),3),
                              'lonlat':[round(v,10) for v in local_to_lonlat(xy,self.site['anchor_lonlat'])],
                              'xy':[round(v,5) for v in xy]})
                made+=1
        layer=calculate_area_crowd_weight(areas,users)
        public_areas=[]
        for area in areas:
            stats=layer[area['id']]
            public_areas.append({k:v for k,v in area.items() if k!='share'}|{
                'geojson_geometry':{'type':'Polygon','coordinates':[[local_to_lonlat(p,self.site['anchor_lonlat']) for p in area['polygon'][0]]]},
                'user_count':counts[area['id']],'weighted_users':round(stats['weighted_users'],4),'density':round(stats['density'],6)})
        timestamp=observed_at or datetime.now(timezone.utc).isoformat().replace('+00:00','Z')
        return {
            'snapshot_id':f'hotspot-{self.seed}-{self.user_count}',
            'simulated':True,'observed_at':timestamp,'user_count':len(users),
            'total_weight':round(sum(u['weight'] for u in users),4),
            'users':users,'areas':public_areas,
            'source':{'kind':'station_node_hotspot_sampling','tables':['station_nodes'],'area_count':len(areas),
                      'description':f'{len(users)} user dummy berbobot di sekitar gerbang tap, eskalator, tangga, lift, pintu masuk (radius 2.5–4 m dari station_nodes) dan koridor crowd survei. Simulasi, bukan sensor.'},
            'routing_transform':{'purpose':'Tidak ada transformasi: crowd dan routing memakai koordinat station_nodes yang sama.','rotation_degrees':0},
        }
