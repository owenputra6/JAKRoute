"""Metre geometry for a small indoor site. No external GIS dependencies.

GeoJSON rings support holes. All path segments are checked, not only nodes.
The local projection is suitable for a station-sized footprint, not city routing.
"""
import math
from .errors import RouteError

EPS = 1e-8

def distance(a, b):
    return math.hypot(a[0]-b[0], a[1]-b[1])

def local_to_lonlat(p, anchor):
    lon, lat = anchor
    return [lon + p[0]/(111320*math.cos(math.radians(lat))), lat + p[1]/111320]

def lonlat_to_local(p, anchor):
    lon, lat = anchor
    return [(p[0]-lon)*111320*math.cos(math.radians(lat)), (p[1]-lat)*111320]

def point_segment_distance(p, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]
    t = ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy) if dx or dy else 0
    t = max(0, min(1, t))
    return distance(p, (a[0]+t*dx, a[1]+t*dy))

def ring_edges(ring):
    return zip(ring, ring[1:]+ring[:1])

def on_ring(p, ring):
    return any(point_segment_distance(p, a, b) < EPS for a, b in ring_edges(ring))

def in_ring(p, ring):
    if on_ring(p, ring):
        return True
    x, y = p
    inside = False
    for a, b in ring_edges(ring):
        if (a[1]>y) != (b[1]>y) and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]:
            inside = not inside
    return inside

def in_polygon(p, rings):
    return in_ring(p, rings[0]) and not any(in_ring(p, r) for r in rings[1:])

def cross(a,b,c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])

def intersects(a,b,c,d):
    u,v,w,z = cross(a,b,c), cross(a,b,d), cross(c,d,a), cross(c,d,b)
    if ((u>EPS and v < -EPS) or (u < -EPS and v>EPS)) and ((w>EPS and z < -EPS) or (w < -EPS and z>EPS)):
        return True
    return (abs(u)<EPS and point_segment_distance(c,a,b)<EPS or
            abs(v)<EPS and point_segment_distance(d,a,b)<EPS or
            abs(w)<EPS and point_segment_distance(a,c,d)<EPS or
            abs(z)<EPS and point_segment_distance(b,c,d)<EPS)

def segment_distance(a,b,c,d):
    if intersects(a,b,c,d): return 0.0
    return min(point_segment_distance(a,c,d), point_segment_distance(b,c,d),
               point_segment_distance(c,a,b), point_segment_distance(d,a,b))

def segment_safe(a,b,walkables,obstacles,clearance=0.25):
    # Require a whole segment to lie inside a single walkable polygon.
    # Connect adjoining areas through explicit door/portal nodes, or union them first.
    contained = False
    for rings in walkables:
        if not all(in_polygon(p,rings) for p in (a,b,((a[0]+b[0])/2,(a[1]+b[1])/2))):
            continue
        # Grid is inset from outer boundaries; boundary crossings are disallowed.
        if any(intersects(a,b,c,d) for ring in rings for c,d in ring_edges(ring)):
            continue
        contained = True
        break
    if not contained: return False
    for rings in obstacles:
        if in_polygon(a,rings) or in_polygon(b,rings): return False
        if any(segment_distance(a,b,c,d) <= clearance+EPS for ring in rings for c,d in ring_edges(ring)):
            return False
    return True

def ring_area(ring):
    return abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in ring_edges(ring)))/2

def polygon_area(rings):
    return ring_area(rings[0])-sum(ring_area(r) for r in rings[1:])

def geojson_polygons(geojson, anchor):
    polygons=[]
    for feature in geojson["features"]:
        geom=feature["geometry"]
        if geom["type"] not in ("Polygon","MultiPolygon"):
            raise RouteError("invalid_geometry", "Polygon/MultiPolygon diperlukan.")
        polys=[geom["coordinates"]] if geom["type"]=="Polygon" else geom["coordinates"]
        for rings in polys:
            polygons.append([[lonlat_to_local(p,anchor) for p in ring] for ring in rings])
    return polygons
