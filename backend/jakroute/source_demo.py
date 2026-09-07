"""Obstacle-only proof on the uploaded Anggrek polygons.

The original file has no doors/walkable boundary/floor links. We keep every
polygon as an obstacle and choose two synthetic free-space endpoints.
Never treat room centroids as entrances or label this a usable station route.
"""
from .geometry import geojson_polygons
from .indoor_routing import IndoorRouter
from .providers import load_json

def build_anggrek_demo(data_dir):
    raw=load_json(data_dir/'anggrek_source.geojson')
    anchor=raw['features'][0]['geometry']['coordinates'][0][0]
    polygons=geojson_polygons(raw,anchor)
    pts=[p for poly in polygons for ring in poly for p in ring]
    xmin=min(p[0] for p in pts); xmax=max(p[0] for p in pts)
    ymin=min(p[1] for p in pts); ymax=max(p[1] for p in pts)
    bounds=[xmin-5,ymin-5,xmax+5,ymax+5]
    ring=[[bounds[0],bounds[1]],[bounds[2],bounds[1]],[bounds[2],bounds[3]],[bounds[0],bounds[3]],[bounds[0],bounds[1]]]
    site=dict(id='anggrek_obstacle_test',label='Anggrek: uji obstacle dengan batas dan endpoint buatan',simulated=True,
      anchor_lonlat=anchor,grid_step_m=1,clearance_m=.75,floors=[dict(id=0,bounds=bounds,walkable=[[ring]],obstacles=polygons)],
      places=[dict(id='test_start',label='Start uji',scope='indoor',kind='access',floor=0,xy=[xmin-3,ymax+3]),dict(id='test_goal',label='Goal uji',scope='indoor',kind='access',floor=0,xy=[xmax+3,ymin-3])],
      crowd_areas=[],connectors=[])
    return IndoorRouter(site)
