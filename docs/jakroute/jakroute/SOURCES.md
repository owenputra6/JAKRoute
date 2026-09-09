# Sumber teknis

Diperiksa saat penyusunan paket, 8 September 2026. Tidak ada kredensial dari percakapan
lama yang disalin ke source code.

- OpenAI Responses function calling: https://developers.openai.com/api/docs/guides/function-calling
- Ollama JSON schema: https://docs.ollama.com/capabilities/structured-outputs
- Ollama chat HTTP: https://docs.ollama.com/api/chat
- Ollama Gemma 4: https://ollama.com/library/gemma4
- Ollama Gemma 3 fallback: https://ollama.com/library/gemma3
- Google Weather current conditions: https://developers.google.com/maps/documentation/weather/current-conditions
- Google Weather condition enum: https://developers.google.com/maps/documentation/weather/reference/rest/v1/WeatherCondition
- Supabase Data REST API: https://supabase.com/docs/guides/api
- Supabase API keys: https://supabase.com/docs/guides/getting-started/api-keys
- FastAPI testing: https://fastapi.tiangolo.com/tutorial/testing/
- Flutter HTTP networking: https://docs.flutter.dev/cookbook/networking/fetch-data
- Dart http package: https://pub.dev/packages/http
- MapLibre Flutter package: https://pub.dev/packages/maplibre_gl
- MapLibre controller API: https://pub.dev/documentation/maplibre_gl/latest/maplibre_gl/MapLibreMapController-class.html
- MAPID dokumentasi publik: https://mapid.co.id/docs/download_all?language=eng

Dokumentasi MAPID yang ditemukan menjelaskan fitur routing pada platform, tetapi
belum memberikan kontrak endpoint routing live yang dapat dipastikan untuk akun
pengguna. Karena itu mapid_contract.json tidak diisi endpoint hasil tebakan.

Geometri sumber: file lampiran pengguna “indoor-routing-webgis (1)(3).html”, bagian
const geojson. Polygon disimpan dalam anggrek_source.geojson. Peta simulasi stasiun
adalah fixture baru, tidak menyalin interpretasi fasilitas dari polygon Anggrek.

Sumber crowd: lampiran pengguna “Denah Stasiun Palmerah(3).geojson”. Sembilan polygon
disimpan tanpa perubahan sebagai `palmerah_crowd_areas.geojson`. Properti yang tersedia
hanya `id_tool`, `area_meter_square`, dan `area_hectare`; atribut lantai maupun graph
routing tidak ditambahkan ke file sumber.

Sumber routing Lantai 2 terbaru: lampiran pengguna “Lantai 2 Palmerah Fella.geojson”
(55 Polygon) dan “Titik Titik Penghubung LT 2.geojson” (20 Point). File dipertahankan
di `backend/data`; SQL di `supabase/` mengubah Polygon menjadi `station_blocks` dan
Point menjadi `station_nodes`. Keputusan proyek memperlakukan seluruh block sebagai
obstacle dan point 19–20 sebagai pembentuk koridor crowd.
