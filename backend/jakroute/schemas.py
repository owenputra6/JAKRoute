"""Runtime contracts. Prefer explicit constraints over model guesses."""
from dataclasses import dataclass, field, asdict
import math
from .errors import RouteError

MODES=("best_fit","fastest","min_walk")
LABELS={"best_fit":"Rute Paling Sesuai","fastest":"Rute Paling Cepat","min_walk":"Rute Minim Berjalan Kaki"}

def numeric(value,name,minimum=0,maximum=100000):
    if isinstance(value,bool) or not isinstance(value,(int,float)) or not math.isfinite(value) or not minimum<=value<=maximum:
        raise RouteError("invalid_input",f"{name} harus angka {minimum}–{maximum}.")
    return value

@dataclass
class Preferences:
    avoid_stairs: bool=False
    step_free: bool=False
    preferred_access: str="any"
    time_priority: float=1.0
    walking_priority: float=1.0
    crowd_priority: float=1.0
    max_walk_m: float | None=None
    required_facilities: list[str]=field(default_factory=list)

    @classmethod
    def parse(cls,value):
        value=value or {}
        if not isinstance(value,dict) or set(value)-set(cls.__dataclass_fields__):
            raise RouteError("invalid_preferences","Field preferensi tidak dikenali.")
        p=cls(**value)
        for name in ("avoid_stairs","step_free"):
            if type(getattr(p,name)) is not bool: raise RouteError("invalid_preferences",f"{name} harus boolean.")
        if p.preferred_access not in ("any","elevator","escalator","stairs"):
            raise RouteError("invalid_preferences","Jenis akses tidak valid.")
        for name in ("time_priority","walking_priority","crowd_priority"):
            numeric(getattr(p,name),name,0,5)
        if not p.time_priority+p.walking_priority+p.crowd_priority:
            raise RouteError("invalid_preferences","Setidaknya satu prioritas harus positif.")
        if p.max_walk_m is not None: numeric(p.max_walk_m,"max_walk_m",0,10000)
        if not isinstance(p.required_facilities,list) or len(p.required_facilities)>4 or any(not isinstance(x,str) for x in p.required_facilities):
            raise RouteError("invalid_preferences","Maksimal empat fasilitas wajib.")
        return p

    def as_dict(self): return asdict(self)

def merge_preferences(explicit, inferred):
    # Caller-supplied profile wins on numeric settings; hard constraints can only tighten.
    defaults=Preferences().as_dict()
    explicit=explicit or {}
    inferred=inferred or {}
    # A preference is optional. Models may return null for a priority when the
    # user has not chosen one yet; null means "use the balanced default".
    result={**defaults,**inferred,**explicit}
    for key in ("time_priority","walking_priority","crowd_priority"):
        if result.get(key) is None: result[key]=defaults[key]
    # Some models emit 0 for every unspecified priority. Treat that as no
    # preference rather than rejecting an otherwise routable request.
    if not sum(result.get(key,0) or 0 for key in ("time_priority","walking_priority","crowd_priority")):
        for key in ("time_priority","walking_priority","crowd_priority"):
            result[key]=defaults[key]
    for key in ("avoid_stairs","step_free"):
        result[key]=bool(inferred.get(key)) or bool(explicit.get(key))
    limits=[x.get("max_walk_m") for x in (explicit,inferred) if x.get("max_walk_m") is not None]
    if limits: result["max_walk_m"]=min(limits)
    result["required_facilities"]=list(dict.fromkeys(explicit.get("required_facilities",[])+inferred.get("required_facilities",[])))
    return Preferences.parse(result)
