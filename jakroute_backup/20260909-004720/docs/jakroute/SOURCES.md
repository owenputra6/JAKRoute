# Sumber teknis

Diperiksa saat penyusunan paket, 7 September 2026. Tidak ada kredensial dari percakapan
lama yang disalin ke source code.

- OpenAI Responses function calling: https://developers.openai.com/api/docs/guides/function-calling
- Ollama JSON schema: https://docs.ollama.com/capabilities/structured-outputs
- Ollama chat HTTP: https://docs.ollama.com/api/chat
- Ollama Gemma 4: https://ollama.com/library/gemma4
- Ollama Gemma 3 fallback: https://ollama.com/library/gemma3
- Google Weather current conditions: https://developers.google.com/maps/documentation/weather/current-conditions
- Google Weather condition enum: https://developers.google.com/maps/documentation/weather/reference/rest/v1/WeatherCondition
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
