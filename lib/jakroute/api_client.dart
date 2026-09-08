import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class JakRouteApiException implements Exception {
  final String message;
  final int? statusCode;
  const JakRouteApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class JakRouteApi {
  final String baseUrl;
  final Future<String?> Function()? accessToken;
  final http.Client _client;
  JakRouteApi({required this.baseUrl, this.accessToken, http.Client? client})
      : _client = client ?? http.Client();

  Future<Json> _request(String path, {Json? body}) async {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');
    final token = await accessToken?.call();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    try {
      final response = await (body == null
          ? _client.get(uri, headers: headers)
          : _client.post(uri, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 180));
      final Json payload;
      try {
        payload = Map<String, dynamic>.from(jsonDecode(utf8.decode(response.bodyBytes)) as Map);
      } catch (_) {
        throw JakRouteApiException('Server mengirim respons yang tidak valid.', response.statusCode);
      }
      if (response.statusCode >= 400) {
        final error = payload['error'];
        final message = error is Map ? error['message']?.toString() : null;
        throw JakRouteApiException(message ?? 'Permintaan gagal (${response.statusCode}). Periksa input dan koneksi backend.', response.statusCode);
      }
      return payload;
    } on TimeoutException {
      throw const JakRouteApiException('Permintaan melewati batas waktu. Coba lagi.');
    } on http.ClientException {
      throw const JakRouteApiException('Backend tidak terjangkau. Periksa URL dan jaringan perangkat.');
    }
  }

  Future<Json> catalog() => _request('/catalog');
  Future<Json> health() => _request('/health');
  Future<CrowdSnapshot> crowdSnapshot() async =>
      CrowdSnapshot(await _request('/crowd/snapshot'));
  Future<Recommendation> recommend(Json request) async =>
      Recommendation(await _request('/recommend-route', body: request));
  Future<Json> forumSummary() => _request('/forum/summary');
  Future<Json> sendForumReport(Json report) => _request('/forum/reports', body: report);
  void close() => _client.close();
}
