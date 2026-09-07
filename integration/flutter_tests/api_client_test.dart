import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../../lib/jakroute/api_client.dart';

void main() {
  test('sends profile constraints and uses current user token', () async {
    final api = JakRouteApi(baseUrl: 'https://backend.example', accessToken: () async => 'test-session',
      client: MockClient((request) async {
        expect(request.url.path, '/recommend-route');
        expect(request.headers['Authorization'], 'Bearer test-session');
        expect((jsonDecode(request.body) as Map)['preferences']['step_free'], true);
        return http.Response(jsonEncode({'status': 'clarification_required', 'routes': [], 'question': 'Peron mana?'}), 200);
      }));
    final result = await api.recommend({'preferences': {'step_free': true}});
    expect(result.status, 'clarification_required');
    expect(result.question, 'Peron mana?');
    api.close();
  });

  test('provider errors become user-visible messages', () async {
    final api = JakRouteApi(baseUrl: 'https://backend.example', client: MockClient((_) async =>
        http.Response(jsonEncode({'error': {'message': 'MAPID belum dikonfigurasi.'}}), 503)));
    await expectLater(api.catalog(), throwsA(isA<JakRouteApiException>()));
    api.close();
  });
}
