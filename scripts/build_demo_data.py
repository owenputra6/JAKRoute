"""Regenerate explicitly synthetic station fixtures; never changes source Anggrek."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
DATA=ROOT/'backend'/'data'
def save(name,obj): (DATA/name).write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def poly(x0,y0,x1,y1): return [[[x0,y0],[x1,y0],[x1,y1],[x0,y1],[x0,y0]]]
places=[]
def place(id,label,xy,floor=0,kind='access',scope='indoor'):
 places.append(dict(id=id,label=label,xy=xy,floor=floor,kind=kind,scope=scope))
place('entrance_west','Pintu barat',[2,16],kind='entrance')
place('entrance_east','Pintu timur',[58,16],kind='entrance')
place('toilet_01','Toilet',[8,4],kind='toilet')
place('mushola_01','Mushola',[8,28],kind='mushola')
place('platform_1','Peron 1',[56,16],1,'platform')
place('platform_2','Peron 2',[42,16],1,'platform')
for kind,y in [('stairs',4),('escalator',16),('elevator',28)]:
 for floor in (0,1): place(f'{kind}_{floor}',f'{kind} lantai {floor}',[52,y],floor,kind)
place('outside_west','Titik luar barat (simulasi)',[-40,16],kind='outdoor',scope='outdoor')
place('outside_east','Titik luar timur (simulasi)',[100,16],kind='outdoor',scope='outdoor')
areas=[dict(id='north',floor=0,polygon=poly(0,0,60,10)),dict(id='south',floor=0,polygon=poly(0,24,60,32)),dict(id='west',floor=0,polygon=poly(0,10,24,24)),dict(id='east',floor=0,polygon=poly(36,10,60,24)),dict(id='platform_area',floor=1,polygon=poly(0,0,60,32))]
site=dict(id='demo_station',label='Stasiun simulasi — bukan denah Palmerah',simulated=True,anchor_lonlat=[106.7812,-6.2019],grid_step_m=2,clearance_m=.25,floor_height_m=4,
 floors=[dict(id=0,bounds=[0,0,60,32],walkable=[poly(0,0,60,32)],obstacles=[poly(24,10,36,24)]),dict(id=1,bounds=[0,0,60,32],walkable=[poly(0,0,60,32)],obstacles=[])],places=places,crowd_areas=areas,
 connectors=[dict(id=f'{kind}_link',kind=kind,**{'from':f'{kind}_0','to':f'{kind}_1'},duration_s=dur,walking_m=walk,bidirectional=(kind!='escalator'),available=True) for kind,dur,walk in [('stairs',14,8),('escalator',12,0),('elevator',45,0)]])
save('station_demo.json',site)
users=[dict(id=f'u{i:03}',xy=[10+(i%10)*.5,3+(i//10)*.5],floor=0,weight=1+(i%3)*.25) for i in range(60)]
users+=[dict(id='south_1',xy=[12,28],floor=0,weight=1.4),dict(id='p_1',xy=[50,16],floor=1,weight=1.0)]
save('crowd_users.json',dict(simulated=True,observed_at='2026-09-07T08:00:00Z',users=users))
save('weather_dummy.json',dict(source='dummy',simulated=True,condition='RAIN',is_raining=True,observed_at='2026-09-07T08:00:00Z',location_label='Area simulasi'))
inc=dict(incident_id='escalator_link:failure',resource_id='escalator_link',category='failure',summary='Eskalator menuju peron dilaporkan rusak. Gunakan akses lain yang sesuai kebutuhan pengguna.',effect='unavailable',routing_code=0,status='active',last_report_at='2026-09-07T08:00:00Z',evidence_ids=['report_001'],resolution_claimed=False)
save('forum_summary_seed.json',dict(summary='Eskalator menuju peron dilaporkan rusak dan belum ada konfirmasi perbaikan petugas.',incidents=[inc],simulated=True))
reports=[dict(report_id='report_001',resource_id='escalator_link',observed_at='2026-09-07T08:00:00Z',message='Eskalator ke peron rusak, penumpang lewat tangga.'),dict(report_id='report_002',resource_id='escalator_link',observed_at='2026-09-07T08:10:00Z',message='Eskalatornya masih mati.'),dict(report_id='report_003',resource_id='escalator_link',observed_at='2026-09-07T08:20:00Z',message='Kayaknya sudah diperbaiki deh.'),dict(report_id='report_004',resource_id='north',observed_at='2026-09-07T08:25:00Z',message='Ada api dan asap pekat di koridor utara, jalur tidak dapat dilewati.')]
save('forum_reports.json',reports)
(DATA/'forum_simulasi.txt').write_text('SIMULASI — semua kejadian berikut fiktif.\n\n'+'\n'.join(f"{r['observed_at']} | {r['report_id']} | {r['resource_id']} | Penumpang: {r['message']}" for r in reports)+'\n2026-09-07T08:30:00Z | PETUGAS TERVERIFIKASI (endpoint terpisah): Eskalator telah diperbaiki.\n',encoding='utf-8')
save('mapid_contract.json',dict(configured=False,url='',method='POST',headers={'Authorization':'${api_key}'},query={},body={'origin':['${origin_lon}','${origin_lat}'],'destination':['${destination_lon}','${destination_lat}']},response={'coordinates_path':'geometry.coordinates','distance_path':'distance_m','duration_path':'duration_s','distance_multiplier':1,'duration_multiplier':1},note='Template internal, bukan klaim schema MAPID. Isi sesuai kontrak resmi akun Anda. Koordinat output harus LineString [longitude,latitude].'))
print('Generated station fixtures')
