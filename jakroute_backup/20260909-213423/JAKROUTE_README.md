# JAKRoute — paket Flutter + Python

Paket implementasi prototype seluruh lapisan: routing Python, tiga alternatif rute,
summary forum OpenAI, OpenAI function calling, 100 titik crowd berbobot dari area
GeoJSON Palmerah, integrasi `station_locations` Supabase, FastAPI, dan modul Flutter.
Mulai melalui mode demo tanpa key. Backend Python tetap berjalan sebagai server
terpisah walaupun foldernya diletakkan di project Flutter.

**Status pengujian:** lihat `verification/TEST_REPORT.md`. Network routing indoor
masih demo. Sembilan polygon Palmerah mempertahankan koordinat dan luas sumber,
tetapi hanya digunakan untuk sampling crowd—bukan dianggap sebagai network jalan.
API live dan build aplikasi Flutter tetap perlu diverifikasi di mesinmu.

## Jalankan di Windows

Gunakan Python 3.12 dan project Flutter milikmu yang sudah bisa dibuka. Ekstrak ZIP
utuh ke folder sementara. Dari folder hasil ekstrak, jalankan:

```powershell
python scripts/install_into_flutter.py "C:\Users\owen\flutter_testing\flutter_application_1"
```

Pemasang menyalin folder, menambahkan izin internet Android, dan mengizinkan HTTP
untuk build **debug**. File yang bentrok dicadangkan ke `jakroute_backup`. `main.dart`
dan `pubspec.yaml` milikmu tetap dipertahankan. Jangan mengarahkan target ke folder
paket ini sendiri. Alternatif manual: gabungkan `backend`, `notebooks`, `lib`, dan
`scripts` ke root project Flutter; ikuti pengaturan Android di `integration`.

Pindah ke root project Flutter, lalu jalankan di terminal pertama:

```powershell
flutter pub add http
flutter pub add maplibre_gl:0.26.2
.\scripts\jakroute_setup.ps1
.\scripts\jakroute_run.ps1
```

Jika PowerShell tidak mengizinkan skrip lokal, jalankan perintah Python setara dari
bagian “Manual backend” di bawah; tidak perlu mengubah kebijakan PowerShell.
Pemasangan package `maplibre_gl` memerlukan versi Flutter/Dart yang didukung
package. Paket ini tidak mengganti konfigurasi Gradle project lama secara otomatis.

Biarkan terminal backend tetap menyala. Di terminal kedua pada root Flutter:

```powershell
flutter run -t lib/main_jakroute_demo.dart --dart-define=BACKEND_URL=http://10.0.2.2:8000
```

`10.0.2.2` adalah akses host dari emulator Android. Untuk HP fisik, gunakan IP LAN
komputer backend, misalnya `http://192.168.1.10:8000`, pada jaringan yang sama.
Untuk Flutter web atau simulator iOS di host yang sama gunakan `http://localhost:8000`.
Flutter web dapat memakai port 8080 agar cocok dengan CORS default.

Endpoint pengecekan: `http://localhost:8000/health`. Dokumentasi endpoint:
`http://localhost:8000/docs`. Tekan **Bandingkan tiga rute** pada layar demo.

## Apa yang sudah bisa dicoba

- Ke Peron 1 dari pintu barat: tampil tiga kriteria, meskipun beberapa geometri sama.
- Hindari tangga + eskalator rusak: semua pilihan yang valid memakai lift.
- Akses bebas anak tangga: lift dipilih; eskalator juga tidak memenuhi batasan ini.
- Ke peron tanpa nomor: jika tujuan tidak dipilih, sistem meminta klarifikasi.
- Masuk dari titik outdoor lalu ke peron: ada sambungan outdoor–indoor dan warning hujan.
- Outdoor ke outdoor dengan singgah toilet: ada outdoor–indoor–outdoor.
- Jalur/fasilitas dengan kode `-1`: dikeluarkan dari pencarian semua mode.
- Panel **Keramaian simulasi**: 100 titik dengan bobot per orang dan angka per area.
- Kartu **AI Insight**: alasan route, personalisasi, waktu, jarak, dan paparan crowd.

Peta dasar MAPID opsional. Diagram indoor sudah tersedia tanpa style URL. Untuk
memakai style milikmu, tambahkan argumen berikut pada `flutter run`:

```powershell
--dart-define="MAPID_STYLE_URL=https://basemap.mapid.io/styles/street-2d-building/style.json?key=YOUR_BASEMAP_KEY"
```

Key basemap untuk klien berbeda peruntukan dari key routing server. Jangan memasukkan
OpenAI API key, kredensial petugas, atau secret backend ke Dart.

## Manual backend

Di root project Flutter:

```powershell
python -m venv backend/.venv
backend/.venv/Scripts/python.exe -m pip install -r backend/requirements-dev.txt
Copy-Item backend/.env.example backend/.env
cd backend
.venv/Scripts/python.exe -m pytest -q
.venv/Scripts/python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000
```

Salin `.env.example` hanya jika `.env` belum ada. Pada macOS/Linux, gunakan
`backend/.venv/bin/python` sebagai executable Python virtual environment.

## Urutan fase

| Fase | Yang dijalankan | Bukti yang dilihat |
|---|---|---|
| 1. Routing | `00_routing_tests.ipynb` dan `python -m pytest -q` | Rute, geometri, perbedaan jarak/waktu, constraint |
| 2A. Forum AI | `01_forum_openai.ipynb` | Report → summary terstruktur, persistensi insiden, konfirmasi petugas |
| 2B. Route AI | `02_openai_function_calling.ipynb` | Pilihan fungsi, parameter, hasil backend, alasan |
| 3. Backend | `uvicorn main:app` | Endpoint `/recommend-route`, `/catalog`, forum |
| 4. Flutter | `main_jakroute_demo.dart` | Form, tiga rute, warning, per lantai, peta |
| 5. Server | `backend/Dockerfile` / `compose.yaml` | URL backend HTTPS yang dapat diakses app |

Untuk notebook, pilih interpreter virtual environment backend di VS Code/Jupyter.
Notebook sudah memuat output simulasi. Simpan file dalam struktur folder lengkap.

## Mengaktifkan AI asli

Edit `backend/.env`; restart backend setelah perubahan.

**OpenAI:** isi `OPENAI_API_KEY`, `OPENAI_MODEL` yang tersedia di akunmu dan mendukung
Responses + function calling, lalu ubah `AGENT_MODE=openai`. Notebook 02 sudah live-only
dan akan berhenti jika key/model belum tersedia. Paket tidak menyisipkan key atau mengklaim
API sudah berhasil dipanggil. Mode demo menggunakan parser terbatas yang jelas diberi label.

**Forum AI:** gunakan OpenAI API agar notebook dapat langsung menerima report tanpa
menjalankan model lokal. Isi `OPENAI_API_KEY` dan `OPENAI_MODEL` pada `backend/.env`,
lalu buka `notebooks/01_forum_openai.ipynb` dan ubah `RUN_LIVE_OPENAI=True`.
Output forum dibatasi `160` token dan hanya summary terstruktur yang masuk ke state.

**Ollama (opsional/legacy):** jika ingin membandingkan model lokal, install Ollama:

```powershell
ollama pull gemma4:e4b
ollama serve
```

Jika Ollama sudah berjalan sebagai aplikasi, tidak perlu menjalankan server kedua.
OpenAI route agent tetap menggunakan summary terstruktur; ia tidak membaca laporan
forum mentah dan tidak memiliki tool untuk mengambil/mengubah insiden.

## Mengaktifkan provider nyata

**MAPID routing:** set `MAPID_MODE=live`, isi `MAPID_API_KEY`, lalu isi
`backend/data/mapid_contract.json` sesuai endpoint, metode, parameter dan respons
routing yang benar dari akun/dokumentasi MAPID. `configured` baru diubah `true`
setelah mapping benar. File tersebut adalah template adaptor internal, **bukan
schema resmi MAPID**. Endpoint live tidak bisa dipastikan dari lampiran. URL
basemap bukan endpoint routing. Mode live gagal jelas bila belum dikonfigurasi;
tidak pernah diam-diam mengembalikan simulasi.

**Google Weather:** set `WEATHER_MODE=google` dan isi `GOOGLE_WEATHER_API_KEY` untuk
API Weather yang sudah diaktifkan. Data cuaca hanya menghasilkan warning pada
segmen outdoor. Tidak ada penalti cuaca, bonus teduh, atau perubahan geometri
berdasarkan hujan. Data yang tidak tersedia ditampilkan sebagai tidak tersedia.
Lookup memakai anchor Palmerah `[106.7974118, -6.20749225]` dengan kontrak urutan
`[longitude, latitude]`; angka longitude `107.797...` dari `main2.dart` tidak dipakai.

**Supabase station data:** set `STATION_DATA_MODE=supabase`, `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, dan bila perlu `SUPABASE_STATION_TABLE`. Backend membaca field
`id, source_id, name, category, latitude, longitude, floor, area_m2`. Baris dengan
`source_id` yang cocok akan memperkaya label node routing. Baris lain tetap dikirim
sebagai data lokasi, tetapi tidak dijadikan node karena belum memiliki koneksi graph.
Flutter dapat tetap memakai Supabase Auth melalui callback token seperti contoh di
bawah; secret OpenAI/cuaca tidak masuk APK.

**Crowd GeoJSON:** `palmerah_crowd_areas.geojson` menghasilkan tepat 100 user saat
backend start. `CROWD_SEED` mengontrol hasil yang reproducible. Setiap user memiliki
bobot sendiri; density area = jumlah bobot / `area_meter_square`. Karena GeoJSON
tidak memiliki floor, seluruh titik ditandai floor 0 pada prototype.

**Denah nyata:** ganti dataset sesuai kontrak `docs/DATA_GUIDE.md`. Saat pindah site,
gunakan database forum terpisah dengan `DB_PATH`; state dari site lain ditolak.
File `station_demo.json` tetap menjadi nama sumber konfigurasi untuk prototype ini.

## Memasukkan layar ke app milikmu

Setelah demo berjalan, gunakan `JakRouteScreen` di navigasi app existing. Tidak perlu
memindahkan logika Python ke Dart. Contoh di sebuah screen/route Dart:

```dart
import 'jakroute/jakroute.dart';

final api = JakRouteApi(baseUrl: 'https://your-backend.example');
final page = JakRouteScreen(api: api, mapStyleUrl: yourMapidStyleUrl);
```

Buat `api` sekali pada state/provider lalu panggil `api.close()` saat lifecycle
pemilik berakhir. Untuk Supabase Auth yang sudah kamu pakai:

```dart
final api = JakRouteApi(
  baseUrl: 'https://your-backend.example',
  accessToken: () async => Supabase.instance.client.auth.currentSession?.accessToken,
);
```

App host menyediakan import/initialization Supabase. Di server set
`AUTH_MODE=supabase`, `SUPABASE_URL`, dan `SUPABASE_ANON_KEY`. Backend memverifikasi
sesi pengguna ke Supabase; role petugas tidak diterima dari body request.

## Bagian yang tetap perlu verifikasi milikmu

- Request API live: key/model OpenAI, MAPID routing, Google Weather. Ollama hanya
  diperlukan untuk notebook legacy jika ingin membandingkan local inference.
- Data stasiun asli: walkable area, pintu, floor, fasilitas, dan connector yang nyata.
- Build Flutter/Gradle di project existing. Pemeriksaan Dart dalam paket bersifat
  sintaks dan review sumber, bukan bukti APK sudah berhasil dibangun.
- Deploy backend beserta URL HTTPS; app Flutter tidak menjalankan server Python.

Batas sistem saat ini adalah routing pejalan di luar + indoor satu stasiun. Belum
ada routing/jadwal antarstasiun KRL, pelacakan GPS indoor, maupun data keramaian live;
100 titik yang tampil adalah simulasi reproducible dari geometri area Palmerah.
Katalog mengikat lokasi ke ID; untuk lokasi luar baru tambahkan titik dengan
koordinat pada katalog. Semua tiga objective pada perjalanan outdoor murni akan
mengikuti kandidat provider yang tersedia; tidak diklaim sebagai tiga optimasi
outdoor independen.

Dokumen detail: `docs/ARCHITECTURE.md`, `docs/DATA_GUIDE.md`, `docs/DEPLOYMENT.md`,
`docs/FILE_INDEX.md`, `docs/UPDATE_2026-09-08.md`, dan `verification/TEST_REPORT.md`. Setelah pemasangan lewat
skrip, dokumen `docs` ditempatkan di `docs/jakroute` dalam project existing.
