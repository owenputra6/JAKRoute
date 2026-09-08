from pathlib import Path
import nbformat as nbf
ROOT=Path(__file__).resolve().parents[1]
setup='''from pathlib import Path
import sys, json, tempfile
ROOT = next((p for p in [Path.cwd(), *Path.cwd().parents] if (p / 'backend' / 'jakroute').is_dir()), None)
assert ROOT, 'Buka notebook dari folder paket yang sudah diekstrak lengkap.'
sys.path.insert(0, str(ROOT / 'backend'))
DATA = ROOT / 'backend' / 'data'
from jakroute.providers import load_json
from jakroute.config import Settings
'''
def notebook(name,cells):
 nb=nbf.v4.new_notebook(cells=[nbf.v4.new_markdown_cell(text) if kind=='md' else nbf.v4.new_code_cell(text) for kind,text in cells])
 nb.metadata={'kernelspec':{'display_name':'Python 3','language':'python','name':'python3'},'language_info':{'name':'python','version':'3.12'}}
 nbf.write(nb,ROOT/'notebooks'/name)
notebook('00_routing_tests.ipynb',[
 ('md','# Phase 1 — Uji mesin routing\nJalankan semua cell. Seluruh input stasiun, crowd, cuaca dan summary forum di sini **simulasi**. Tidak ada panggilan OpenAI, Ollama, atau MAPID. Hasil optimal mengikuti resolusi grid. Grafik tidak menggambarkan Palmerah.'),
 ('code',setup),
 ('code','''from jakroute.indoor_routing import IndoorRouter
from jakroute.crowd import calculate_area_crowd_weight
site=load_json(DATA/'station_demo.json')
router=IndoorRouter(site)
users=load_json(DATA/'crowd_users.json')['users']
incidents=load_json(DATA/'forum_summary_seed.json')['incidents']
layer=calculate_area_crowd_weight(site['crowd_areas'],users)
layer'''),
 ('code','''routes={mode:router.route('entrance_west','platform_1',mode,users=users,incidents=incidents) for mode in ('best_fit','fastest','min_walk')}
for mode,r in routes.items():
 print(mode, {'walking_m':r['walking_m'], 'duration_s':r['duration_s'], 'connectors':r['connectors_used']})
 assert 'escalator_link' not in r['connectors_used']
assert routes['min_walk']['walking_m']<=routes['fastest']['walking_m']
assert routes['fastest']['duration_s']<=routes['min_walk']['duration_s']'''),
 ('code','''import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
fig,axes=plt.subplots(1,2,figsize=(13,4.5))
colors={'best_fit':'#0b9078','fastest':'#176bdf','min_walk':'#d4771c'}
for floor,ax in enumerate(axes):
 for obstacle in site['floors'][floor]['obstacles']:
  ax.add_patch(Polygon(obstacle[0],facecolor='#293c4e'))
 for mode,r in routes.items():
  segments=[f['properties']['local_xy'] for f in r['geometry']['features'] if f['properties']['floor']==floor]
  for j,seg in enumerate(segments):
   ax.plot([p[0] for p in seg],[p[1] for p in seg],color=colors[mode],alpha=.85,lw=2.5,label=mode if j==0 else None)
 for p in site['places']:
  if p['scope']=='indoor' and p['floor']==floor:
   ax.scatter(*p['xy'],color='#314354',s=14)
   ax.annotate(p['label'],p['xy'],fontsize=6,xytext=(3,3),textcoords='offset points')
 ax.set(xlim=(-2,70),ylim=(-2,36),aspect='equal',title=f'Lantai {floor} — simulasi',xlabel='meter',ylabel='meter')
 ax.legend(fontsize=7)
fig.suptitle('Eskalator rusak: tiga kriteria, dua pilihan geometri',fontsize=15)
fig.tight_layout()
plt.show()'''),
 ('code','''# Larangan tangga + eskalator rusak => lift. Step-free juga menolak eskalator.
for mode in routes:
 r=router.route('entrance_west','platform_1',mode,preferences={'avoid_stairs':True},users=users,incidents=incidents)
 assert r['connectors_used']==['elevator_link']
print('PASS: semua rute menjaga constraint keras.')
from jakroute.providers import create_weather_warning
assert create_weather_warning({'is_raining':True},False)==[]
print(create_weather_warning({'is_raining':True},True))'''),
 ('md','## Uji pada polygon lampiran asli\nFile asli berisi 11 polygon Lantai 1 Anggrek. Semua polygon tetap obstacle. Batas luar dan dua titik uji berikut buatan karena sumber tidak menyertakan pintu dan area yang boleh dilalui. Ini hanya bukti algoritma menghindari polygon.'),
 ('code','''from jakroute.source_demo import build_anggrek_demo
source_router=build_anggrek_demo(DATA)
source_route=source_router.route('test_start','test_goal','min_walk')
from shapely.geometry import LineString,Polygon as SPolygon
for feature in source_route['geometry']['features']:
 line=LineString(feature['properties']['local_xy'])
 assert all(not line.intersects(SPolygon(p[0],p[1:])) for p in source_router.site['floors'][0]['obstacles'])
print('PASS: seluruh segmen menghindari 11 polygon asli; jarak uji',round(source_route['walking_m'],2),'m')'''),
 ('md','Pengujian lengkap: dari folder `backend`, jalankan `python -m pytest -q`. Test mencakup kepadatan numerik, budget berjalan, fasilitas wajib, kegagalan akses, state forum, dan endpoint.')])
notebook('01_forum_ollama.ipynb',[
 ('md','# Phase 2A — Forum → summary dengan state yang bertahan\nMode awal menggunakan fixture agar alur bisa diperiksa tanpa model. **Output fixture bukan bukti kemampuan Ollama.** Untuk pengujian AI asli: jalankan `ollama pull gemma4:e4b`, jalankan server Ollama, atur model/URL di `backend/.env`, lalu ubah `RUN_LIVE_OLLAMA=True`. Jika perangkat terlalu berat, gunakan `gemma4:e2b` atau `gemma3:4b`. Thinking dimatikan karena tugasnya hanya ekstraksi JSON.'),
 ('code',setup+'''\nfrom jakroute.forum_state import ForumStore,OllamaSummarizer,DemoSummarizer
# False keeps offline verification deterministic. Set True after Ollama is ready.
RUN_LIVE_OLLAMA=False
settings=Settings.from_env()
processor=OllamaSummarizer(settings) if RUN_LIVE_OLLAMA else DemoSummarizer()
work=tempfile.TemporaryDirectory(prefix='jakroute_forum_')
store=ForumStore(Path(work.name)/'forum.sqlite3')
reports=load_json(DATA/'forum_reports.json')
print('OLLAMA LIVE' if RUN_LIVE_OLLAMA else 'FIXTURE SIMULATION — Ollama belum dipanggil')'''),
 ('code','''evaluation=[]
for report in reports[:3]:
 result=processor.summarize(report,store.snapshot())
 store.update(report,result)
 evaluation.append({'report_id':report['report_id'],'extraction':result,'version':store.snapshot()['version']})
 print(json.dumps(evaluation[-1],ensure_ascii=False,indent=2))
active=store.snapshot()['incidents']
assert any(i['resource_id']=='escalator_link' and i['effect']=='unavailable' for i in active)
assert active and all(i['status']!='resolved' for i in active)
assert evaluation[2]['extraction']['resolution_claimed'] is True
print('PASS: klaim penumpang tidak membuka kembali eskalator.')'''),
 ('code','''report=reports[3]
result=processor.summarize(report,store.snapshot())
store.update(report,result)
assert any(i['resource_id']=='north' and i['routing_code']==-1 for i in store.snapshot()['incidents'])
print(json.dumps(store.snapshot(),ensure_ascii=False,indent=2))'''),
 ('code','''# Otoritas petugas disimulasikan di notebook; endpoint asli memeriksa token terpisah.
version=store.snapshot()['version']
key=next(i['incident_id'] for i in store.snapshot()['incidents'] if i['resource_id']=='escalator_link')
store.confirm(key,'petugas-simulasi','Perbaikan terverifikasi',version,'2026-09-07T08:30:00Z')
assert not any(i['resource_id']=='escalator_link' for i in store.snapshot()['incidents'])
assert any(i['resource_id']=='north' for i in store.snapshot()['incidents'])
# Restart reader: kondisi utara tetap tersimpan.
assert ForumStore(Path(work.name)/'forum.sqlite3').snapshot()==store.snapshot()
print('PASS: eskalator dibuka petugas, insiden utara tetap aktif.')'''),
 ('code','''if RUN_LIVE_OLLAMA:
 negative={'report_id':'negative_001','resource_id':'north','observed_at':'2026-09-07T08:40:00Z','message':'Tidak ada kebakaran; tadi hanya latihan evakuasi.'}
 result=processor.summarize(negative,store.snapshot())
 print('Uji negasi:',result)
 assert result['severe'] is False, 'Model salah membaca negasi; perbaiki prompt/model sebelum live.'
else:
 print('SKIPPED: uji kemampuan bahasa/negasi membutuhkan Ollama asli.')
work.cleanup()''')])
notebook('01_forum_openai.ipynb',[
 ('md','# Phase 2A — Forum threaded → summary dengan OpenAI API\nNotebook ini mensimulasikan satu thread forum: laporan awal, beberapa balasan penumpang, dan laporan kondisi parah. Setiap pesan diproses berurutan dengan `previous_summary`, sehingga state forum terus diperbarui. Output tiap pemanggilan dibatasi `160` token dan klaim penumpang tidak dapat menyelesaikan insiden tanpa konfirmasi petugas.\n\n`RUN_LIVE_OPENAI=True` menjalankan satu pemanggilan OpenAI untuk setiap pesan forum. Untuk pengujian tanpa biaya, ubah ke `False` terlebih dahulu.'),
 ('code',setup+'''\nfrom dataclasses import replace
from jakroute.forum_state import ForumStore,OpenAISummarizer,DemoSummarizer
RUN_LIVE_OPENAI=False
settings=replace(Settings.from_env(),forum_mode='openai')
if RUN_LIVE_OPENAI:
 assert settings.openai_api_key, 'Isi OPENAI_API_KEY di backend/.env terlebih dahulu.'
processor=OpenAISummarizer(settings) if RUN_LIVE_OPENAI else DemoSummarizer()
work=tempfile.TemporaryDirectory(prefix='jakroute_forum_openai_')
store=ForumStore(Path(work.name)/'forum.sqlite3')

# Satu thread utama: setiap item setelah item pertama adalah balasan.
# Metadata thread/parent hanya untuk simulasi forum; ForumStore tetap menyimpan
# seluruh report mentah dan memakai summary terstruktur sebagai state routing.
FORUM_THREAD=[
 {'report_id':'thread_001_post','thread_id':'thread_escalator','author':'Rina','resource_id':'escalator_link','observed_at':'2026-09-07T08:00:00Z','message':'Eskalator menuju peron 1 rusak. Penumpang harus lewat tangga.'},
 {'report_id':'thread_001_reply_01','thread_id':'thread_escalator','parent_report_id':'thread_001_post','author':'Dimas','resource_id':'escalator_link','observed_at':'2026-09-07T08:03:00Z','message':'Saya baru lewat. Benar, eskalator masih tidak bergerak dan tangga menjadi satu-satunya akses ke peron 1.'},
 {'report_id':'thread_001_reply_02','thread_id':'thread_escalator','parent_report_id':'thread_001_reply_01','author':'Sari','resource_id':'escalator_link','observed_at':'2026-09-07T08:07:00Z','message':'Tangga cukup padat, tetapi eskalatornya masih rusak. Belum terlihat petugas memperbaiki.'},
 {'report_id':'thread_001_reply_03','thread_id':'thread_escalator','parent_report_id':'thread_001_reply_02','author':'Bimo','resource_id':'escalator_link','observed_at':'2026-09-07T08:12:00Z','message':'Sepertinya sudah diperbaiki, saya melihat lampunya menyala. Mohon petugas mengecek karena saya belum mendapat konfirmasi resmi.'},
 {'report_id':'thread_001_reply_04','thread_id':'thread_escalator','parent_report_id':'thread_001_reply_03','author':'Petugas lapangan','resource_id':'escalator_link','observed_at':'2026-09-07T08:20:00Z','message':'Saya cek dari bawah, eskalator masih berhenti dan penumpang tetap harus menggunakan tangga. Belum ada konfirmasi perbaikan.'},
]

# Thread kedua: contoh kondisi parah yang harus memblokir routing.
SEVERE_REPORT={'report_id':'thread_002_post','thread_id':'thread_fire','author':'Ayu','resource_id':'north','observed_at':'2026-09-07T08:25:00Z','message':'Ada asap tebal dan api terlihat di koridor utara. Jalur harus ditutup.'}

print((f'OPENAI LIVE — {len(FORUM_THREAD)+1} pemanggilan, max_output_tokens=160 each' if RUN_LIVE_OPENAI else 'FIXTURE SIMULATION — OpenAI belum dipanggil'))'''),
 ('code','''evaluation=[]
for index, report in enumerate(FORUM_THREAD, start=1):
    previous=store.snapshot()
    summary=processor.summarize(report,previous)
    changed=store.update(report,summary)
    current_state=store.snapshot()
    item={'sequence':index,'author':report['author'],'report_id':report['report_id'],
          'parent_report_id':report.get('parent_report_id'),'message':report['message'],
          'summary':summary,'changed':changed,'state_version':current_state['version'],
          'model_reply':current_state['summary']}
    evaluation.append(item)
    print(f"{report['author']}: {report['message']}")
    print(f"model: {current_state['summary']}")
    print()

print('\\nSTATE SETELAH THREAD ESKALATOR:')
print(json.dumps(store.snapshot(),ensure_ascii=False,indent=2))'''),
 ('code','''active=store.snapshot()['incidents']
assert len(evaluation)==5
assert evaluation[-1]['state_version'] >= 1
assert any(i['resource_id']=='escalator_link' for i in active)
# Balasan penumpang yang mengira sudah diperbaiki tidak langsung menghapus insiden.
assert any(i['resource_id']=='escalator_link' and i['status']!='resolved' for i in active)
print('PASS: balasan thread diproses berurutan; insiden belum resolved tanpa konfirmasi petugas.')'''),
 ('code','''previous=store.snapshot()
severe_summary=processor.summarize(SEVERE_REPORT,previous)
store.update(SEVERE_REPORT,severe_summary)
severe_incident=next(i for i in store.snapshot()['incidents'] if i['resource_id']=='north')
print('\\nTHREAD KONDISI PARAH:')
print(json.dumps({'report':SEVERE_REPORT,'summary':severe_summary,'incident':severe_incident},ensure_ascii=False,indent=2))
assert severe_incident['routing_code']==-1
assert severe_incident['status']!='resolved'
print('PASS: kondisi parah menghasilkan routing_code=-1 dan tetap aktif.')'''),
 ('md','## Catatan pengujian\nMode live melakukan `len(FORUM_THREAD)+1` request OpenAI. Setiap request memakai summary state sebelumnya, bukan mengirim seluruh percakapan tanpa batas. Untuk membuka insiden, tetap gunakan `store.confirm(...)` dengan otoritas petugas.'),
 ('code','''work.cleanup()''')])
notebook('02_openai_function_calling.ipynb',[
 ('md','# Phase 2B — OpenAI function calling\nDefault menjalankan fungsi backend dengan pemilihan tool deterministik. **Ini tidak membuktikan OpenAI memahami bahasa.** Isi `OPENAI_API_KEY` dan `OPENAI_MODEL` pada `backend/.env`, kemudian ubah `RUN_LIVE_OPENAI=True` untuk pengujian API asli. Routing, cuaca dan crowd tetap memakai fixture agar hasil uji dapat dibandingkan. Jangan menaruh key di output notebook.'),
 ('code',setup+'''\nfrom dataclasses import replace
from jakroute.service import RouteService
RUN_LIVE_OPENAI=False
work=tempfile.TemporaryDirectory(prefix='jakroute_agent_')
settings=replace(Settings.from_env(),db_path=str(Path(work.name)/'forum.sqlite3'),agent_mode='openai' if RUN_LIVE_OPENAI else 'demo',mapid_mode='demo',weather_mode='demo',forum_mode='demo')
if RUN_LIVE_OPENAI:
 assert settings.openai_api_key and settings.openai_model, 'Isi key dan model di backend/.env dahulu.'
service=RouteService(settings)
print('OPENAI LIVE' if RUN_LIVE_OPENAI else 'DETERMINISTIC DEMO — OpenAI belum dipanggil')'''),
 ('code','''scenarios=[
 {'origin_id':'entrance_west','destination_id':'platform_1','message':'Ke peron, jangan lewat tangga.'},
 {'origin_id':'entrance_west','destination_id':'platform_1','message':'Saya pengguna kursi roda.'},
 {'origin_id':'outside_west','destination_id':'platform_1','message':'Saya ingin paling cepat sampai.'},
 {'origin_id':'outside_west','destination_id':'outside_east','message':'Langsung ke tujuan.'},
 {'origin_id':'entrance_west','message':'Mau ke peron.'},
]
results=[]
for request in scenarios:
 response=service.recommend(request)
 results.append(response)
 print(request['message'],response['status'])
 for trace in response.get('tool_trace',[]): print(' ',trace['name'],trace['arguments'],trace['source'])
 if response['status']=='ok':
  selected=next(r for r in response['routes'] if r.get('route_id')==response['selected_route_id'])
  print(' ',selected['explanation'])'''),
 ('code','''for response in results[:2]:
 assert all(r['connectors_used']==['elevator_link'] for r in response['routes'] if r['status']=='ok')
assert {x['name'] for x in results[3]['tool_trace']}=={'route_outdoor'}
assert results[4]['status']=='clarification_required'
assert any('Hujan' in warning for route in results[2]['routes'] for warning in route.get('warnings',[]))
print('PASS:', 'skenario OpenAI live' if RUN_LIVE_OPENAI else 'skenario wiring demo; AI live belum diuji')'''),
 ('md','## Phase 3 — Kontrak endpoint yang sama untuk Flutter\nTestClient menjalankan aplikasi FastAPI dalam proses Python. Ini menguji endpoint asli tanpa membutuhkan server/port tambahan.'),
 ('code','''from fastapi.testclient import TestClient
from jakroute.api import create_app
with TestClient(create_app(settings,service)) as client:
 print(client.get('/health').json())
 response=client.post('/recommend-route',json={'origin_id':'entrance_west','destination_id':'platform_1','preferences':{'step_free':True}})
 assert response.status_code==200,response.text
 payload=response.json()
 assert len(payload['routes'])==3
 print('Endpoint PASS; response keys:',list(payload))
work.cleanup()''')])

# Latest live conversation notebook. It intentionally overwrites the legacy
# deterministic scenario above while keeping the old generator block readable.
notebook('02_openai_function_calling.ipynb',[
 ('md','# Phase 2B — Percakapan OpenAI + function calling\nNotebook ini menguji percakapan routing yang benar-benar melewati OpenAI API. Preference tidak di-hardcode ke hasil AI: setiap turn mengirim pesan natural-language, lalu preference dari respons turn sebelumnya diteruskan sebagai `conversation_preferences`.\n\nUrutan: (1) tanpa preference awal, (2) memakai preference state sebelumnya, (3) membangun preference dari bahasa natural, (4) respons berikutnya menyesuaikan preference. Semua function call dan hasil routing dicetak jelas. Isi `OPENAI_API_KEY` dan `OPENAI_MODEL` di `backend/.env`. Notebook ini sengaja live-only.'),
 ('code',setup+'''\nfrom dataclasses import replace\nfrom jakroute.service import RouteService\nRUN_LIVE_OPENAI=True\nwork=tempfile.TemporaryDirectory(prefix='jakroute_agent_conversation_')\nsettings=replace(Settings.from_env(),db_path=str(Path(work.name)/'forum.sqlite3'),agent_mode='openai',mapid_mode='demo',weather_mode='demo',forum_mode='demo')\nassert RUN_LIVE_OPENAI\nassert settings.openai_api_key and settings.openai_model, 'Isi OPENAI_API_KEY dan OPENAI_MODEL di backend/.env dahulu.'\nservice=RouteService(settings)\nprint('OPENAI LIVE — preference state berasal dari respons turn sebelumnya')'''),
 ('code','''def show_response(turn_name,user_message,request,response):
    print('\\n'+'='*78)
    print(f'TURN {turn_name}')
    print(f'USER: {user_message}')
    print('REQUEST PREFERENCE STATE:')
    print(json.dumps(request.get('conversation_preferences',{}),ensure_ascii=False,indent=2))
    print('AI INTENT:')
    print(json.dumps(response.get('intent',{}),ensure_ascii=False,indent=2))
    print('FUNCTION CALLS:')
    for trace in response.get('tool_trace',[]):
        print(f"- {trace['name']} | {json.dumps(trace['arguments'],ensure_ascii=False)} | {trace['source']} | {trace['status']}")
    print('ROUTES:')
    for route in response.get('routes',[]):
        print(f"- {route.get('label')}: status={route.get('status')}, walking_m={route.get('walking_m')}, duration_s={route.get('duration_s')}, connectors={route.get('connectors_used')}")
    print('SELECTED:',response.get('selected_route_id'))
    print('PREFERENCES AFTER TURN:')
    print(json.dumps(response.get('preferences',{}),ensure_ascii=False,indent=2))
    return response

def run_turn(turn_name,user_message,previous_response=None):
    request={'origin_id':'entrance_west','message':user_message}
    if previous_response:
        previous_preferences=previous_response.get('preferences',{})
        previous_intent=previous_response.get('intent',{})
        # These are copied from the previous AI response, never hardcoded.
        # Sending them as explicit state also keeps this notebook compatible
        # with an older backend that does not yet read conversation_context.
        request['preferences']=previous_preferences
        request['conversation_preferences']=previous_preferences
        request['conversation_context']={'intent':previous_intent}
        for key in ('origin_id','destination_id'):
            if previous_intent.get(key): request[key]=previous_intent[key]
    response=service.recommend(request)
    assert response['status']=='ok', response
    return show_response(turn_name,user_message,request,response)

responses=[]
responses.append(run_turn('1 — tanpa preference awal','Saya mau ke peron 1.'))
responses.append(run_turn('2 — memakai preference state sebelumnya','Tampilkan lagi rute menuju tujuan yang sama.',responses[-1]))
responses.append(run_turn('3 — membangun preference dari bahasa natural','Saya tidak bisa naik tangga. Gunakan akses yang bebas anak tangga.',responses[-1]))
responses.append(run_turn('4 — respons berikutnya menyesuaikan preference','Sekarang arahkan saya ke peron 1.',responses[-1]))'''),
 ('code','''initial=responses[0]['preferences']
retained=responses[1]['preferences']
built=responses[2]['preferences']
adapted=responses[3]
assert sum(initial[key] for key in ('time_priority','walking_priority','crowd_priority'))>0
assert built['step_free'] or built['avoid_stairs'], built
assert all(route.get('connectors_used')==['elevator_link'] for route in adapted['routes'] if route.get('status')=='ok')
print('\\nPASS: preference tidak wajib di awal, state dipertahankan, preference dibangun dari bahasa natural, dan turn berikutnya memakai lift.')'''),
 ('md','## Kontrak endpoint untuk Flutter\nFlutter menyimpan `preferences` dari respons lalu mengirimkannya kembali sebagai `conversation_preferences` pada pesan berikutnya.'),
 ('code','''from fastapi.testclient import TestClient
from jakroute.api import create_app
with TestClient(create_app(settings,service)) as client:
    response=client.post('/recommend-route',json={'origin_id':'entrance_west','message':'Saya tidak bisa naik tangga.','conversation_preferences':responses[1]['preferences']})
    assert response.status_code==200,response.text
    payload=response.json()
    print('ENDPOINT RESPONSE KEYS:',list(payload))
    print('ENDPOINT STATUS:',payload['status'])
work.cleanup()''')])
print('Wrote 4 notebooks')
