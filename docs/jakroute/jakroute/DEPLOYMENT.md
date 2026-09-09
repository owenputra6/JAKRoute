# Deployment dan verifikasi Flutter

Backend Python dan aplikasi Flutter dideploy terpisah. Notebook adalah alat uji,
bukan file yang dijalankan di Android/iOS. Menyalin folder backend ke project
Flutter tidak memasukkannya sebagai server di dalam APK.

## Backend

1. Isi backend/.env dengan provider/AI sesuai mode yang ingin dipakai.
2. Untuk backend yang dapat diakses pengguna, set APP_ENV=production dan gunakan
   AUTH_MODE=supabase untuk sesi pengguna. Isi OFFICER_TOKEN yang panjang dan acak.
   AUTH_MODE=token hanya untuk pengujian privat, bukan shared secret dalam app publik.
3. Dari backend, jalankan `docker compose up --build -d`, atau host proses
   `python -m uvicorn main:app --host 0.0.0.0 --port 8000 --workers 1`.
4. Pasang HTTPS pada reverse proxy/platform hosting, lalu gunakan URL HTTPS tersebut
   pada JakRouteApi di Flutter.
5. Volume forum_state menyimpan SQLite agar restart container tidak mereset insiden.
   Jangan menjalankan beberapa replika dengan file SQLite lokal yang berbeda.
6. Forum utama memakai OpenAI API dari backend. Ollama hanya diperlukan jika mode
   legacy `FORUM_MODE=ollama` dipilih. Jangan menaruh OpenAI key di Flutter.

Compose yang disertakan adalah konfigurasi layanan + volume. Paket belum dipublish
ke penyedia hosting manapun. Untuk skala multi-replika, pindahkan ledger ke database
transaksional bersama (misalnya PostgreSQL/Supabase) dan rate limiting bersama.

## Flutter

Paket ini mengunci `maplibre_gl` 0.26.2 karena versi tersebut sudah berhasil dibangun
di project Android pengguna; jangan menaikkan ke 0.27.0 tanpa menyesuaikan Gradle/Kotlin.
Periksa persyaratan platform package untuk versi project yang dipakai. Jangan
mengubah Gradle/JDK secara acak hanya untuk menyamakan contoh; konfigurasi Android
existing harus lolos build lebih dahulu. Sumber: dokumentasi package resmi dalam
SOURCES.md.

Pemasang membuat penambahan debug cleartext HTTP untuk localhost/LAN. Build release
menggunakan backend HTTPS. Izin INTERNET ditambahkan tanpa mengganti app label dan
activity. Untuk iOS lokal, kebijakan jaringan mengikuti project iOS host; paling
mudah menggunakan URL backend HTTPS saat menguji di perangkat.

Perintah verifikasi pada project Flutter setelah pemasangan:

```powershell
flutter pub get
flutter analyze lib/jakroute lib/main_jakroute_demo.dart
flutter test test/jakroute/api_client_test.dart
flutter run -t lib/main_jakroute_demo.dart --dart-define=BACKEND_URL=http://10.0.2.2:8000
```

Peta MAPID baru dimuat bila mapStyleUrl diisi. Diagram floor selalu tersedia.
MapLibre tidak mendukung desktop Windows pada package yang dipakai; gunakan Android,
iOS, atau web. Jangan memakai target desktop Windows untuk menguji peta native ini.

## Apa yang belum dibuktikan oleh paket

- Build APK/iOS tidak dijalankan. Upaya pemeriksaan SDK Flutter di lingkungan
  pembuat paket ditolak peninjauan otomatis karena mencoba mengakses metadata mesin
  cloud. Pemeriksaan sintaks Dart yang tidak membutuhkan akses itu dilakukan.
- Key/model OpenAI, server Ollama legacy, dan akun MAPID/Google Weather tidak tersedia
  untuk uji live. Unit test provider/model menggunakan mock atau fixture berlabel.
- Notebook dieksekusi cell demi cell dalam proses Python karena startup kernel
  Jupyter di lingkungan pembuat paket tidak diizinkan membuat socket. Output dan
  metadata notebook menjelaskan metode ini; bukan hasil menjalankan model AI asli.
- Block dan point Lantai 2 berasal dari GeoJSON pengguna, tetapi boundary walkable
  masih turunan. Indoor positioning, crowd live, dan routing antarestasiun/jadwal KRL
  memerlukan input/layanan tambahan.
- Kredensial Supabase tidak disertakan. Mode live membaca `station_blocks` dan
  `station_nodes` hanya setelah SQL dijalankan dan environment backend diisi.
