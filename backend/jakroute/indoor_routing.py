"""Eight-neighbour grid routing + explicit floor connectors.

Optimality is relative to the configured grid, not continuous free space.
All three modes share the same hard restrictions. -1 is never an edge cost.
"""
import heapq
import math
from shapely.geometry import Polygon, Point, LineString
from shapely.ops import unary_union
from .geometry import distance, segment_safe, in_polygon, local_to_lonlat
from .crowd import calculate_area_crowd_weight, density_at
from .schemas import Preferences, LABELS, MODES
from .errors import RouteError

class IndoorRouter:
    def __init__(self,site):
        self.site=site
        self.nodes={}
        self.adj={}
        self.floors={f["id"]:f for f in site["floors"]}
        self.free={}
        for floor,f in self.floors.items():
            walk=unary_union([Polygon(p[0],p[1:]) for p in f["walkable"]])
            obs=unary_union([Polygon(p[0],p[1:]) for p in f["obstacles"]])
            if not walk.is_valid or not obs.is_valid:
                raise RouteError("invalid_polygon","Perbaiki polygon yang tidak valid terlebih dahulu.")
            self.free[floor]=walk.difference(obs.buffer(site.get("clearance_m",.25)))
        self.places={p["id"]:p for p in site["places"]}
        self._build()

    def _node(self,key,xy,floor,kind="grid"):
        self.nodes[key]={"xy":xy,"floor":floor,"kind":kind}
        self.adj[key]=[]

    def _edge(self,a,b,kind="walk",resource=None,seconds=None,walk=None,bidirectional=True):
        length=distance(self.nodes[a]["xy"],self.nodes[b]["xy"])
        if kind!="walk": length=float(self.site.get("floor_height_m",4))
        e={"to":b,"kind":kind,"resource":resource,"length_m":length,
           "walking_m":length if walk is None else float(walk),"seconds":seconds}
        self.adj[a].append(e)
        if bidirectional: self.adj[b].append({**e,"to":a})

    def _safe(self,a,b,floor):
        geom=Point(a) if distance(a,b)<1e-10 else LineString([a,b])
        return self.free[floor].covers(geom)

    def _build(self):
        step=float(self.site["grid_step_m"])
        if not 0.1<=step<=10: raise RouteError("invalid_grid","Resolusi grid harus 0.1–10 m.")
        grids={}
        for floor,f in self.floors.items():
            xmin,ymin,xmax,ymax=f["bounds"]
            if ((xmax-xmin)/step)*((ymax-ymin)/step)>100000:
                raise RouteError("grid_limit","Grid terlalu besar untuk prototype.")
            grid={}
            for i in range(1,math.ceil((xmax-xmin)/step)):
                for j in range(1,math.ceil((ymax-ymin)/step)):
                    p=[xmin+i*step,ymin+j*step]
                    if self._safe(p,p,floor):
                        key=f"g:{floor}:{i}:{j}"
                        grid[(i,j)]=key
                        self._node(key,p,floor)
            for (i,j),a in grid.items():
                for dx,dy in ((1,0),(0,1),(1,1),(1,-1)):
                    b=grid.get((i+dx,j+dy))
                    if b and self._safe(self.nodes[a]["xy"],self.nodes[b]["xy"],floor): self._edge(a,b)
            grids[floor]=list(grid.values())
        for p in self.site["places"]:
            if p["scope"]!="indoor": continue
            if not self._safe(p["xy"],p["xy"],p["floor"]):
                raise RouteError("invalid_place",f"{p['id']} berada di obstacle/luar walkable.")
            self._node(p["id"],p["xy"],p["floor"],p["kind"])
            nearby=sorted(grids[p["floor"]],key=lambda k:distance(p["xy"],self.nodes[k]["xy"]))
            connected=0
            for k in nearby:
                if distance(p["xy"],self.nodes[k]["xy"])>step*2: break
                if self._safe(p["xy"],self.nodes[k]["xy"],p["floor"]):
                    self._edge(p["id"],k)
                    connected+=1
                    if connected==8: break
            if not connected: raise RouteError("disconnected_place",f"{p['id']} tidak terhubung ke grid.")
        for c in self.site["connectors"]:
            a,b=c["from"],c["to"]
            if a not in self.nodes or b not in self.nodes or c["kind"] not in ("stairs","elevator","escalator"):
                raise RouteError("invalid_connector","Koneksi antarlantai tidak valid.")
            if c["duration_s"]<0 or c["walking_m"]<0:
                raise RouteError("invalid_connector","Jarak/waktu konektor tidak boleh negatif.")
            self._edge(a,b,c["kind"],c["id"],c["duration_s"],c["walking_m"],c.get("bidirectional",True))

    def _restriction(self,a,e,prefs,incidents):
        if prefs.avoid_stairs and e["kind"]=="stairs": return "Tangga dihindari"
        if prefs.step_free and e["kind"] in ("stairs","escalator"): return "Perlu akses bebas anak tangga"
        connector=next((c for c in self.site["connectors"] if c["id"]==e["resource"]),None)
        if connector and not connector.get("available",True): return "Akses tidak tersedia"
        for inc in incidents:
            if inc["status"]=="resolved": continue
            if inc["effect"] not in ("unavailable","blocked") and inc["routing_code"]!=-1: continue
            target=inc["resource_id"]
            if target in (a,e["to"],e["resource"]): return inc["summary"]
            area=next((x for x in self.site["crowd_areas"] if x["id"]==target),None)
            if area and self.nodes[a]["floor"]==area["floor"]:
                # Check subsegments densely along a grid edge; area interiors + boundaries.
                pa,pb=self.nodes[a]["xy"],self.nodes[e["to"]]["xy"]
                from .geometry import intersects, ring_edges
                if in_polygon(pa,area["polygon"]) or in_polygon(pb,area["polygon"]) or any(intersects(pa,pb,c,d) for ring in area["polygon"] for c,d in ring_edges(ring)):
                    return inc["summary"]
        return None

    def _metrics(self,a,e,layer,prefs,incidents):
        b=e["to"]
        pa,pb=self.nodes[a]["xy"],self.nodes[b]["xy"]
        floor=self.nodes[a]["floor"]
        # Integrate occupancy over edge length instead of counting a whole area each time.
        count=max(1,math.ceil(e["length_m"]/0.5))
        density=sum(density_at([pa[0]+(pb[0]-pa[0])*(i+.5)/count,pa[1]+(pb[1]-pa[1])*(i+.5)/count],floor,self.site["crowd_areas"],layer) for i in range(count))/count
        base=e["seconds"] if e["seconds"] is not None else e["length_m"]/1.2
        duration=base*(1+1.5*density) if e["kind"]!="elevator" else base*(1+0.5*density)
        caution=sum(20 for inc in incidents if inc["status"]!="resolved" and inc["effect"]=="caution" and inc["resource_id"] in (a,b,e["resource"]))
        duration+=caution
        exposure=density*e["length_m"]
        access=0 if prefs.preferred_access in ("any",e["kind"]) or e["kind"]=="walk" else 1.5
        cost=prefs.time_priority*duration/60+prefs.walking_priority*e["walking_m"]/100+prefs.crowd_priority*exposure/100+access
        return {"duration_s":duration,"crowd_exposure":exposure,"density":density,"cost":cost}

    def route(self,origin,destination,mode="best_fit",preferences=None,users=None,incidents=None):
        if mode not in MODES: raise RouteError("invalid_mode","Mode rute tidak dikenali.")
        prefs=preferences if isinstance(preferences,Preferences) else Preferences.parse(preferences)
        incidents=incidents or []
        if origin not in self.nodes or destination not in self.nodes:
            raise RouteError("unknown_place","Asal/tujuan indoor tidak ditemukan.")
        for endpoint in (origin,destination):
            test_edge={"to":endpoint,"kind":"walk","resource":None}
            if self._restriction(endpoint,test_edge,prefs,incidents):
                raise RouteError("no_route","Asal atau tujuan berada pada akses yang ditutup.")
        layer=calculate_area_crowd_weight(self.site["crowd_areas"],users or [])
        required=list(dict.fromkeys(prefs.required_facilities))
        masks={k:sum(1<<i for i,r in enumerate(required) if r in (k,n["kind"])) for k,n in self.nodes.items()}
        if any(not any(m&(1<<i) for m in masks.values()) for i in range(len(required))):
            raise RouteError("unknown_facility","Fasilitas wajib tidak ditemukan.")
        all_mask=(1<<len(required))-1
        # Pareto labels preserve feasible paths under a hard walking budget.
        labels=[{"node":origin,"mask":masks[origin],"score":0.0,"walk":0.0,"duration":0.0,"prev":None,"edge":None,"metrics":None}]
        frontier={(origin,masks[origin]):[0]}
        heap=[(0.0,0.0,0)]
        winner=None
        metrics_cache={}
        while heap:
            _,_,idx=heapq.heappop(heap)
            label=labels[idx]
            a,mask=label["node"],label["mask"]
            if idx not in frontier[(a,mask)]: continue
            if a==destination and mask==all_mask:
                winner=idx
                break
            for pos,e in enumerate(self.adj[a]):
                if self._restriction(a,e,prefs,incidents): continue
                key=(a,pos)
                if key not in metrics_cache: metrics_cache[key]=self._metrics(a,e,layer,prefs,incidents)
                m=metrics_cache[key]
                walk=label["walk"]+e["walking_m"]
                if prefs.max_walk_m is not None and walk>prefs.max_walk_m+1e-8: continue
                increment=e["walking_m"] if mode=="min_walk" else m["duration_s"] if mode=="fastest" else m["cost"]
                score=label["score"]+increment
                duration=label["duration"]+m["duration_s"]
                state=(e["to"],mask|masks[e["to"]])
                prior=frontier.setdefault(state,[])
                def dominates(old):
                    if prefs.max_walk_m is not None:
                        return old["score"]<=score+1e-9 and old["walk"]<=walk+1e-9
                    # min_walk ties do not depend on crowd; stable graph order wins.
                    return old["score"]<=score+1e-9
                if any(dominates(labels[i]) for i in prior): continue
                prior[:]=[i for i in prior if not (score<=labels[i]["score"]+1e-9 and (prefs.max_walk_m is None or walk<=labels[i]["walk"]+1e-9))]
                new={"node":state[0],"mask":state[1],"score":score,"walk":walk,"duration":duration,"prev":idx,"edge":e,"metrics":m}
                ni=len(labels); labels.append(new); prior.append(ni)
                heapq.heappush(heap,(score,walk,ni))
                if len(labels)>300000: raise RouteError("search_limit","Pencarian terlalu besar; kurangi fasilitas wajib/resolusi grid.")
        if winner is None: raise RouteError("no_route","Tidak ada rute yang memenuhi seluruh batasan dan kondisi akses.")
        steps=[]; cursor=winner
        while labels[cursor]["prev"] is not None:
            cur=labels[cursor]; prev=labels[cur["prev"]]
            steps.append({"from":prev["node"],"to":cur["node"],**cur["edge"],**cur["metrics"]})
            cursor=cur["prev"]
        steps.reverse()
        self.validate(steps,prefs,incidents)
        features=[]
        for s in steps:
            a,b=self.nodes[s["from"]],self.nodes[s["to"]]
            features.append({"type":"Feature","geometry":{"type":"LineString","coordinates":[local_to_lonlat(a["xy"],self.site["anchor_lonlat"]),local_to_lonlat(b["xy"],self.site["anchor_lonlat"])]},
                "properties":{"scope":"indoor","floor":a["floor"],"to_floor":b["floor"],"access":s["kind"],"resource_id":s["resource"],"density":round(s["density"],5),"local_xy":[a["xy"],b["xy"]]}})
        facility_ids=list(dict.fromkeys(k for s in steps for k in (s["from"],s["to"]) if k in self.places))
        connectors=list(dict.fromkeys(s["resource"] for s in steps if s["resource"]))
        return {"route_id":f"{origin}:{destination}:{mode}","mode":mode,"label":LABELS[mode],"status":"ok","origin":origin,"destination":destination,
                "walking_m":round(labels[winner]["walk"],3),"distance_m":round(sum(s["length_m"] for s in steps),3),
                "duration_s":round(labels[winner]["duration"],3),"score":round(labels[winner]["score"],5),
                "crowd_exposure":round(sum(s["crowd_exposure"] for s in steps),5),"facilities_used":facility_ids,"connectors_used":connectors,
                "geometry":{"type":"FeatureCollection","features":features},"valid":True,"source":"indoor_python_grid","simulated":self.site["simulated"],"steps":steps}

    def validate(self,steps,prefs,incidents):
        for i,s in enumerate(steps):
            if i and steps[i-1]["to"]!=s["from"]: raise RouteError("route_invalid","Segmen terputus.")
            if self._restriction(s["from"],s,prefs,incidents): raise RouteError("route_invalid","Rute melanggar batasan akses.")
            a,b=self.nodes[s["from"]],self.nodes[s["to"]]
            if s["kind"]=="walk" and (a["floor"]!=b["floor"] or not self._safe(a["xy"],b["xy"],a["floor"])):
                raise RouteError("route_invalid","Segmen menembus obstacle atau berpindah lantai tanpa konektor.")
        return True

def calculate_plain_shortest_path(router,origin,destination,**kwargs):
    return router.route(origin,destination,"min_walk",**kwargs)

def calculate_personalized_indoor_route(router,origin,destination,mode="best_fit",**kwargs):
    if mode not in ("best_fit","fastest"): raise RouteError("invalid_mode","Mode weighted harus best_fit/fastest.")
    return router.route(origin,destination,mode,**kwargs)
