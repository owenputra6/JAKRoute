# Kontrak sistem dan cakupan

## Alur perjalanan

Flutter mengirim permintaan/profil ke FastAPI. Agent menafsirkan permintaan dan
hanya boleh memanggil `route_outdoor`, `route_indoor_plain`, dan
`route_indoor_personalized`. Backend menyediakan constraint, snapshot crowd dan
summary forum ke fungsi yang sesuai. Hasil geometri berasal dari routing dan
melalui pemeriksaan obstacle/konektivitas.

Ada satu grid otomatis per lantai, dibatasi polygon walkable dan obstacle dengan
clearance. Lift, tangga dan eskalator menghubungkan lantai melalui connector
beridentitas. Memiliki koordinat XY yang sama tidak otomatis menghubungkan dua
lantai. Gerak diagonal juga diperiksa sehingga tidak memotong sudut obstacle.

Solver memakai pencarian Dijkstra pada grid delapan arah dengan state fasilitas
wajib. Batas berjalan memakai label Pareto (cost dan jarak berjalan) supaya jalur
yang lebih mahal tetapi memenuhi budget tidak dibuang. Optimalitas relatif terhadap
resolusi grid. Grid 2 m demo perlu diperhalus untuk data indoor asli.

## Tiga objective

| Mode | Objective | Yang tetap menjadi constraint keras |
|---|---|---|
| min_walk | Jumlah jarak **berjalan**; lift/eskalator bergerak memiliki walking cost 0 | Obstacle, akses tutup, step-free, larangan tangga, batas berjalan, fasilitas wajib |
| fastest | Durasi, termasuk perlambatan kepadatan dan waktu connector | Sama |
| best_fit | Jumlah cost berdasarkan prioritas waktu, berjalan, keramaian, akses pilihan | Sama |

Keramaian per area = total bobot user / luas polygon area yang dapat digunakan (m²).
Jangan menghitung satu user beberapa kali dalam satu snapshot. Luas memakai
`area_meter_square` dari GeoJSON sebagai nilai sumber. Data user mencantumkan posisi,
lantai, bobot, area dan waktu snapshot. Bobot keramaian penghuni berbeda dengan
bobot preferensi pengguna pencari rute.

Saat backend start, `GeoJsonCrowdSimulator` mengambil tepat 100 titik deterministik
di dalam 9 polygon Palmerah. Setiap area mendapat minimal satu titik; sisanya dibagi
proporsional terhadap luas. Setiap titik mendapat bobot numerik sendiri. Tidak ada
konversi menjadi label low/medium/high. Snapshot yang sama dipakai seluruh alternatif
rute dan dikirim ke Flutter melalui `/crowd/snapshot`.

GeoJSON tidak berisi lantai atau network jalur. Posisi asli `[lon,lat]` dipertahankan,
sedangkan salinannya dirotasi dan diskalakan ke floor 0 graph demo untuk evaluasi
weighted path. Transformasi itu tidak mengubah luas sumber dan tidak berarti polygon
GeoJSON telah menjadi denah routing lengkap.

Parameter waktu demo: berjalan dasar 1.2 m/s; perlambatan jalan = durasi dasar ×
(1 + 1.5 × density). Elevator memakai durasi dasar × (1 + 0.5 × density) sebagai
simulasi antrean. Angka tersebut asumsi simulasi, belum model waktu yang dikalibrasi.
Paparan crowd dihitung sepanjang segmen menggunakan sampling maksimum 0.5 m.

Cost best_fit = time_priority × duration/60 + walking_priority × walking/100
+ crowd_priority × exposure/100 + penalti 1.5 jika jenis connector tidak sesuai
akses pilihan. Semua komponen nonnegatif. Besaran prioritas 0–5. Penalti pilihan
akses bersifat preferensi; step-free/avoid_stairs bersifat constraint keras.

Semua mode tetap memeriksa summary forum. Eskalator rusak diblokir pada connector
eskalator, bukan diubah menjadi tangga. Tangga/lift adalah connector lain dengan
geometrinya sendiri. Rute minim berjalan dapat memilih tangga/lift hanya jika
memenuhi seluruh constraint. Jika tidak ada rute valid, hasil `no_route`.

Cuaca hanya warning outdoor. Tidak mengubah cost, jarak, atau pilihan geometri.
Data hujan aktual yang tidak tersedia tidak diasumsikan cerah. Dalam prototype
satu stasiun, lookup cuaca pada anchor area stasiun; perjalanan jauh memerlukan
cakupan lokasi/waktu cuaca yang lebih luas.

Koordinat cuaca berasal dari anchor site `[longitude, latitude]`. Anchor demo kini
berada di area GeoJSON Palmerah (`106.797...`, bukan typo `107.797...`). Google key
disimpan di backend. Cuaca tidak dipanggil untuk perjalanan indoor penuh.

## Supabase station data

Mode `STATION_DATA_MODE=supabase` membaca tabel `station_locations` lewat REST dari
backend. `source_id` yang sama dengan ID graph dapat memperkaya label/metadata titik.
Koordinat Supabase yang belum memiliki node/edge tetap dikembalikan sebagai katalog,
tetapi tidak boleh otomatis dirutekan. Ini mencegah AI mengarang konektivitas hanya
dari sebuah titik koordinat. Mode live tidak fallback diam-diam ke fixture.

## Forum terpisah

Laporan mentah → OpenAI structured extraction → ledger SQLite → summary aktif.
Ollama tetap tersedia sebagai adaptor pembanding, tetapi bukan jalur utama.
Route agent hanya menerima summary dengan ID sumber, resource, efek dan status.
Ia tidak mengambil forum aktif, tidak menghitung kepadatan melalui tool, dan
bukan otoritas penyelesaian insiden.

- Efek `unavailable` menutup fasilitas rusak bagi semua mode.
- Kode `-1` menandai `blocked`; edge dikeluarkan, bukan diberi cost negatif.
- Laporan baru yang lebih ringan tidak menurunkan efek aktif tanpa petugas.
- Klaim perbaikan oleh penumpang menandai `awaiting_officer_confirmation`.
- Insiden yang tidak disebut di laporan baru tetap aktif.
- Laporan duplikat idempotent; ID sama dengan isi berbeda ditolak.
- Laporan lama yang tiba setelah konfirmasi petugas tidak membuka insiden lama.
- Laporan baru setelah perbaikan dapat mencatat kejadian berulang.
- `/forum/confirm` memerlukan token petugas terpisah dan versi state yang cocok.

SQLite menyimpan transaksi serta riwayat laporan/konfirmasi. Seluruh alternatif
dalam satu rekomendasi memakai versi summary sama. Bila versi berubah selama
perhitungan, request dihitung ulang sekali, lalu menghasilkan 409 jika masih berubah.
Kondisi dapat berubah sesudah respons dikirim; pengguna perlu meminta rute baru.

Forum summary memakai `max_output_tokens=160`; model hanya mengisi schema kategori,
efek, tingkat keparahan, klaim resolusi, dan summary singkat. Ini membatasi biaya
per-report tanpa memberi AI kewenangan untuk menyelesaikan insiden.

## AI personalization dan function calling

OpenAI melakukan structured intent parsing, lalu function calling sebenarnya
terhadap jobs yang sudah divalidasi. Argumen tool dibatasi ke asal, tujuan, mode.
Hard constraints tidak dapat diubah dari argumen tool. Semua job yang dibutuhkan
untuk tiga alternatif wajib diselesaikan dalam loop terbatas. Job tidak dikenal
ditolak, dan kegagalan model tidak diberi label sebagai hasil AI sukses.

Kata “peron” tanpa nomor tidak menjadi `platform_1` otomatis jika ada dua tujuan
mungkin. Jika profil/request sudah memberi tujuan, AI dapat memilih akses sesuai
profil dan kondisi. Kebutuhan kursi roda tidak disimpulkan dari identitas/nama user.

Penjelasan memakai alasan backend yang memang benar untuk rute terpilih. AI memilih
kode alasan dari daftar yang didukung hasil; kalimatnya dirender dari daftar itu.
AI tidak bebas mengarang angka, fasilitas atau klaim perbaikan. Ini membuat evaluasi
penjelasan lebih mudah dibanding teks bebas yang tidak terikat bukti.

Mode `demo` memakai pemilihan deterministik terbatas, bukan model lokal pengganti
OpenAI. `FORUM_MODE=demo` hanya menerima empat laporan fixture yang persis sama.
Mode live tidak fallback diam-diam ke dummy. Notebook menandai mana pengujian model
asli dan mana pengujian wiring.

## Handoff outdoor–indoor

Origin/tujuan indoor mengaktifkan router indoor. Jika perjalanan outdoor perlu
fasilitas wajib indoor, backend mencoba kombinasi pintu masuk/keluar yang ada.
Untuk setiap kombinasi, tersedia maksimal satu bagian indoor yang mengunjungi
seluruh fasilitas wajib. Kriteria dibandingkan dengan jarak/waktu total termasuk
segmen outdoor. Budget berjalan total mengurangi alokasi indoor setelah panjang
outdoor diketahui. Permintaan outdoor MAPID dicache per pasangan selama request
agar preflight budget dan tool call memakai hasil yang sama.

Respons menyimpan segmen GeoJSON terpisah untuk floor/scope, tidak menggambar
perpindahan lantai sebagai jalan biasa. Respons outdoor live memeriksa titik
provider terhadap titik akses; gap besar ditolak untuk meminta perbaikan titik
handoff. Pemetaan area/titik luar baru dilakukan pada katalog, bukan geocoding AI.

## Endpoint

| Endpoint | Hasil/otoritas |
|---|---|
| GET /health | Mode layanan dan status proses |
| GET /catalog | Site, places, fasilitas, walkable, obstacle |
| GET /crowd/snapshot | 100 titik berbobot, statistik 9 area, provenance dan transform |
| POST /recommend-route | Intent, tiga rute, pilihan, warning, penjelasan, tool trace |
| GET /forum/summary | Summary aktif; tidak mengekspos laporan mentah |
| POST /forum/reports | Proses laporan oleh pipeline forum independen |
| POST /forum/confirm | Konfirmasi petugas terautentikasi + optimistic version |

Cakupan ini tidak memasukkan routing/jadwal kereta antarestasiun, indoor positioning,
ataupun live crowd ingestion. Kebutuhan tersebut membutuhkan sumber data lanjutan.
