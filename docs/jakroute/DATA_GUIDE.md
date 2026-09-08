# Data dan konfigurasi provider

## Data tersedia

| File | Isi dan provenance |
|---|---|
| station_demo.json | Denah dua lantai, grid, ruang jalan, obstacle, fasilitas, connector; seluruhnya simulasi |
| palmerah_crowd_areas.geojson | 9 polygon Palmerah: `id_tool`, `area_meter_square`, `area_hectare`; sumber 100 titik crowd |
| anggrek_source.geojson | 11 polygon diekstrak dari HTML lampiran tanpa perubahan koordinat/atribut |
| crowd_users.json | Fixture crowd lama untuk unit test kompatibilitas; runtime memakai generator GeoJSON |
| weather_dummy.json | Snapshot hujan simulasi |
| forum_simulasi.txt | Cerita forum simulasi yang dapat dibaca langsung |
| forum_reports.json | Laporan simulasi terstruktur sesuai input endpoint |
| forum_summary_seed.json | Kondisi eskalator rusak untuk awal demo |
| mapid_contract.json | Template adapter HTTP; endpoint dan schema asli harus diisi |

GeoJSON Palmerah memiliki 9 Polygon dengan ID `Tap in`, `A-2` sampai `A-9` dan total
luas atribut 819 m². File tidak memiliki atribut lantai, nama fasilitas lengkap,
walkable/obstacle, pintu, atau connector. Karena itu file dipakai hanya untuk sampling
100 titik crowd dan luas density. Network routing tetap `station_demo.json`.

Sumber HTML lama menyebut Lantai 1 Anggrek, bukan Palmerah. Ia tidak menyediakan polygon
walkable, pintu, atau connector antarlantai. Uji sumber tidak menghapus polygon
ruang asal/tujuan agar centroid dapat dilalui. Titik uji ditempatkan di ruang bebas
buatan dan hasil tidak dinyatakan sebagai navigasi bangunan yang terverifikasi.

## Mengganti denah dengan data nyata

Isi kontrak site yang sama dengan station_demo.json. Satuan geometri internal
adalah **meter lokal**. `anchor_lonlat` berupa [longitude, latitude]; output GeoJSON
menggunakan urutan yang sama. Fungsi `lonlat_to_local` dan `local_to_lonlat` tersedia
pada geometry.py untuk skala satu stasiun.

| Field site | Kebutuhan |
|---|---|
| id / label / simulated | Identitas site, nama yang benar, flag data dummy |
| grid_step_m | Resolusi; lebih kecil meningkatkan detail dan jumlah node |
| clearance_m | Jarak buffer terhadap obstacle |
| floors | ID lantai, bounds, list polygon walkable dan obstacle |
| places | id, label, scope indoor/outdoor, kind, xy, floor |
| connectors | id, from, to, kind, duration_s, walking_m, bidirectional, available |
| crowd_areas | id, floor, polygon ruang yang dapat ditempati pengguna |

Format polygon: list rings; ring pertama boundary, ring berikutnya lubang. Polygon
sempit/pintu yang lebih kecil dari resolusi perlu grid lebih halus dan access point
yang benar. Jangan menganggap semua polygon fasilitas sebagai ruangan terlarang.
Klasifikasikan walkable, obstacle, fasilitas dan pintu sesuai makna datanya.

Semua tempat indoor dihubungkan otomatis ke grid lantainya jika geometri valid.
Koneksi lantai hanya lewat connector eksplisit. `step_free` membutuhkan elevator;
eskalator tetap memiliki anak tangga. `walking_m` untuk lift/eskalator bergerak
boleh 0; waktu tunggu/perjalanan tetap dimasukkan ke `duration_s` connector.
Jarak berjalan di pendekatan/pintu lift berasal dari edge grid.

Jika sumber memakai stairs atau eskalator satu arah, isi `bidirectional=false`.
Jika memakai aksesibilitas pintu yang lebih rinci (lebar, kemiringan), tambahkan
aturan sesuai data nyata sebelum mengklaim tingkat aksesibilitas tersebut.

Area crowd tidak boleh saling tumpang tindih. Setiap user harus berada dalam tepat
satu area pada lantainya. Gunakan luas ruang yang benar-benar dapat ditempati,
tidak memasukkan dinding. Bobot per user harus nonnegatif dan finite. Angka bobot
dummy bukan hasil kamera atau hasil pengukuran di Palmerah.

Saat mengganti site, gunakan DB_PATH baru agar gangguan demo tidak tercampur.
`ForumStore` mengikat database ke ID site dan menolak site berbeda. Data crowd
serta resource pada laporan juga harus menggunakan ID site yang baru.

## Supabase `station_locations`

Mode live membaca kolom berikut: `id`, `source_id`, `name`, `category`, `latitude`,
`longitude`, `floor`, `area_m2`. Isi `.env` backend:

```dotenv
STATION_DATA_MODE=supabase
SUPABASE_URL=https://PROJECT.supabase.co
SUPABASE_ANON_KEY=...
SUPABASE_STATION_TABLE=station_locations
```

`source_id` adalah penghubung ke `places[].id` dalam graph. Tanpa kecocokan tersebut,
sebuah row tetap data koordinat nyata tetapi belum routable. Aktifkan Row Level Security
dan kebijakan SELECT sesuai kebutuhan anon/authenticated project. Jangan menyimpan
service-role key di Flutter.

## Adaptor MAPID

Template tidak mengasumsikan endpoint resmi yang tidak tersedia. Isi:

1. `url` HTTPS dan `method` (GET atau POST).
2. `headers`, `query`, `body` sesuai dokumentasi akunmu.
3. Placeholder `${api_key}`, `${origin_lon}`, `${origin_lat}`, `${destination_lon}`,
   `${destination_lat}` dapat digunakan pada nilai di ketiganya.
4. `response.coordinates_path`, `distance_path`, `duration_path` merupakan dotted path
   termasuk indeks array, misalnya `routes.0.geometry.coordinates` **jika benar-benar
   seperti itu responsnya**.
5. `distance_multiplier` dan `duration_multiplier` mengubah satuan ke meter/detik.
6. `configured=true` hanya setelah request/response sudah cocok.

Decoder saat ini menerima coordinates LineString [lon,lat], bukan encoded polyline.
Jika provider mengembalikan encoded geometry, gunakan opsi output GeoJSON resmi
atau tambahkan decoder yang sesuai kontrak provider. Jangan menggunakan URL style
JSON basemap sebagai endpoint routing. Adapter memeriksa format dan gap handoff;
hasil dummy tidak dipakai sebagai pengganti kegagalan mode live.

## Menjalankan forum endpoint

Mode demo menerima salinan persis objek dari forum_reports.json. Mode OpenAI
menerima teks baru dengan schema yang sama. Contoh body:

```json
{
  "report_id": "laporan-unik-001",
  "resource_id": "escalator_link",
  "observed_at": "2026-09-07T08:00:00Z",
  "message": "Eskalator menuju peron rusak."
}
```

Untuk konfirmasi, petugas membaca versi di GET /forum/summary lalu POST /forum/confirm
menggunakan header `X-Officer-Token` yang cocok dengan server:

```json
{
  "incident_id": "escalator_link:failure",
  "expected_version": 0,
  "note": "Perbaikan telah diperiksa petugas."
}
```

Angka versi harus diganti dengan versi aktual. Body tidak menerima field role atau
identitas petugas buatan klien. Petugas pada prototype memakai satu kredensial
operator server; sistem multi-petugas memerlukan autentikasi dan role per petugas.
