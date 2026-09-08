"""Weighted occupancy / usable area. Units: equivalent persons per m²."""
import math
from .geometry import in_polygon, polygon_area
from .errors import RouteError

def calculate_area_crowd_weight(areas, users):
    totals={a["id"]:0.0 for a in areas}
    # A source area can stay authoritative even if its polygon is transformed
    # into the prototype floor for routing and display.
    sizes={a["id"]:float(a.get("area_m2",polygon_area(a["polygon"]))) for a in areas}
    if any(v<=0 for v in sizes.values()):
        raise RouteError("invalid_area", "Luas area harus positif.")
    seen=set()
    for user in users:
        if user["id"] in seen:
            raise RouteError("duplicate_user", "Satu user hanya boleh ada sekali dalam snapshot crowd.")
        seen.add(user["id"])
        weight=user["weight"]
        if isinstance(weight,bool) or not isinstance(weight,(float,int)) or not math.isfinite(weight) or weight<0:
            raise RouteError("invalid_weight", "Bobot user harus angka nonnegatif dan finite.")
        matches=[a for a in areas if a["floor"]==user["floor"] and in_polygon(user["xy"],a["polygon"])]
        if len(matches)!=1:
            raise RouteError("crowd_location", "Setiap posisi dummy user harus berada dalam tepat satu area.")
        totals[matches[0]["id"]]+=weight
    return {k:{"weighted_users":totals[k],"area_m2":sizes[k],"density":totals[k]/sizes[k]} for k in totals}

def density_at(p,floor,areas,layer):
    vals=[layer[a["id"]]["density"] for a in areas if a["floor"]==floor and in_polygon(p,a["polygon"])]
    return max(vals,default=0.0)
