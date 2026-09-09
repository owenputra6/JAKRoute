# Indeks berkas JAKRoute

Paket ini dibagi menurut lapisan yang akan dipindahkan ke project Flutter.

## Yang benar-benar berjalan

- Runtime backend: `backend/main.py`, `backend/jakroute/`, dan `backend/data/`.
- Runtime Flutter: `lib/jakroute/` dan entry point host atau `lib/main_jakroute_demo.dart`.
- `scripts/` hanya setup/run/install; tidak masuk APK.
- `integration/` hanya potongan dependency, manifest, dan test untuk digabung ke app.
- `notebooks/` hanya evaluasi AI/routing; tidak dijalankan pengguna HP.
- `verification/` hanya bukti hasil test; tidak diperlukan saat runtime.
- `docs/` hanya panduan dan kontrak data.

| Lokasi | Isi dan tanggung jawab |
|---|---|
| `backend/jakroute/` | Kode Python canonical untuk routing, state forum, AI adapter, provider cuaca/MAPID, dan service orchestration. |
| `backend/jakroute/indoor_routing.py` | Graph grid indoor, obstacle/dinding, connector, constraint keras, shortest path polos, dan weighted path. |
| `backend/jakroute/crowd.py` | Perhitungan bobot keramaian per user dibagi luas area. Tidak mengubahnya menjadi label low/medium/high. |
| `backend/jakroute/crowd_simulation.py` | Simulator lama berbasis area untuk mode demo dan simulator koridor node 19–20 untuk mode Supabase. |
| `backend/jakroute/station_source.py` | Decoder PostGIS dan pembentuk graph: block → obstacle, point → anchor routing, point 19–20 → koridor crowd. |
| `backend/jakroute/forum_state.py` | Summary OpenAI/Ollama terstruktur, SQLite ledger, versioned incident state, serta aturan konfirmasi petugas. |
| `backend/jakroute/ai_agent.py` | Parsing intent, tiga function OpenAI, bounded tool loop, validasi argument, dan explanation. |
| `backend/jakroute/service.py` | Menggabungkan forum snapshot, crowd, cuaca, indoor/outdoor legs, serta tiga output route. |
| `backend/jakroute/api.py` | FastAPI endpoint, auth, ukuran request, rate limit, dan validasi Pydantic. |
| `backend/data/palmerah_crowd_areas.geojson` | Area sumber asli untuk crowd; bukan network routing. |
| `backend/data/palmerah_lt2_blocks.geojson` | Fixture 55 block untuk verifikasi import/routing Supabase. |
| `backend/data/palmerah_lt2_nodes.geojson` | Fixture 20 point anchor dan koridor crowd. |
| `backend/data/` | Denah routing demo, GeoJSON crowd Palmerah, fixture cuaca/forum, dan template kontrak MAPID. |
| `backend/tests/` | Test obstacle, objective, constraint, forum persistence, API, OpenAI protocol, dan installer. |
| `notebooks/00_routing_tests.ipynb` | Fase 1: uji routing dan visualisasi obstacle/route. |
| `notebooks/01_forum_ollama.ipynb` | Fase 2A: uji summary forum lokal Ollama dan konfirmasi petugas. |
| `notebooks/01_forum_openai.ipynb` | Fase 2A utama: menerima report, membuat summary OpenAI dengan batas output, dan menyimpan state. |
| `notebooks/02_openai_function_calling.ipynb` | Fase 2B: uji pemilihan tiga function dan penjelasan route. |
| `lib/jakroute/` | Client API, model JSON, AI Insight card, visual 100 titik crowd, diagram indoor, dan peta MapLibre opsional. |
| `lib/main_jakroute_demo.dart` | Entry point demo Flutter yang memanggil backend. |
| `integration/` | Dependency Flutter, contoh permission Android debug, dan test client Dart. |
| `supabase/` | Dua SQL berurutan untuk membuat/mengisi `station_blocks` dan `station_nodes`. |
| `scripts/install_into_flutter.py` | Menyalin paket ke project Flutter dan mencadangkan file yang bentrok. |
| `scripts/jakroute_setup.ps1` | Membuat environment backend dan memasang dependency development. |
| `scripts/jakroute_run.ps1` | Menjalankan backend FastAPI dari root project Flutter. |
| `docs/ARCHITECTURE.md` | Kontrak desain dan aturan keputusan route. |
| `docs/DATA_GUIDE.md` | Panduan mengganti data demo dengan data stasiun nyata. |
| `docs/DEPLOYMENT.md` | Pemisahan deployment backend dan Flutter serta batas verifikasi. |
| `docs/SOURCES.md` | Sumber dokumentasi resmi yang dipakai dan provenance fixture. |
| `verification/` | Baseline JUnit lama, hasil pemeriksaan pembaruan, dan gambar demo; baca `TEST_REPORT.md` sebelum mengklaim hasil. |

Urutan kerja yang disarankan adalah `00` → `01` → `02` → FastAPI → Flutter. Backend
tetap proses/server Python terpisah; meletakkan foldernya di root Flutter hanya untuk
kemudahan pengelolaan source.
