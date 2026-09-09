# Laporan verifikasi JAKRoute

Verifikasi pembaruan Supabase routing + crowd dijalankan pada 9 September 2026.

| Pemeriksaan | Hasil |
|---|---|
| Python bytecode compile (`backend/jakroute`, tests, scripts) | **pass** |
| GeoJSON routing | **pass**, 55 Polygon + 20 Point |
| Kontrak import | **pass**, 55 block obstacle + 18 anchor routable + 2 crowd boundary |
| Crowd corridor 19–20 | **pass**, panjang 36,35 m dan lebar 2 m |
| Sampling crowd standard-library harness | **pass**, tepat 100 ID dan 96 bobot unik pada seed test |
| Perhitungan density | **pass**, total bobot dibagi luas koridor 72,70 m² |
| Routing grid harness titik 4 → 18 | **pass**, fastest memilih lintasan berbeda ketika crowd aktif; min-walk tetap pada objective jarak |
| Referensi tabel lama pada runtime/docs aktif | **pass**, tidak ada `station_locations`/`SUPABASE_STATION_TABLE` tersisa selain catatan riwayat update |
| SQL destructive operation | **pass**, tidak ada `DROP TABLE`; tabel lama tidak dihapus |
| Full Python pytest pembaruan | **pass**, 52 passed dalam 28,57 detik; 1 deprecation warning dari Starlette |
| Flutter analyze/build | **jalankan di project Flutter pengguna**; Flutter SDK tidak tersedia di workspace pembuat paket |
| Provider live Supabase, MAPID, Google Weather, OpenAI | **belum dijalankan**; memerlukan kredensial pengguna |

Terdapat 50 fungsi test Python (52 case setelah parametrization), termasuk empat test baru di
`backend/tests/test_supabase_station_graph.py`. Test baru memeriksa pemetaan obstacle,
anchor routing, tepat 100 crowd user berbobot, perubahan rute fastest, dan kestabilan
rute min-walk.

Jalankan dari root project Flutter:

```powershell
.\scripts\jakroute_setup.ps1
flutter analyze lib/jakroute lib/main_jakroute_demo.dart
flutter test test/jakroute/api_client_test.dart
```

`jakroute_setup.ps1` berhenti bila satu test gagal. Hasil JUnit terbaru tersimpan di
`verification/python_tests_20260909.xml`. Uji live memakai konfigurasi
`.env` dan data Supabase milik pengguna; fixture/mock tidak membuktikan koneksi live.
