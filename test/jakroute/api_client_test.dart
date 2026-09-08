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

  test('parses weighted crowd snapshot without categorical condition', () async {
    final api = JakRouteApi(baseUrl: 'https://backend.example', client: MockClient((request) async {
      expect(request.url.path, '/crowd/snapshot');
      return http.Response(jsonEncode({
        'snapshot_id': 'geojson-1-100',
        'simulated': true,
        'observed_at': '2026-09-08T00:00:00Z',
        'user_count': 100,
        'total_weight': 108.5,
        'source': {'file': 'palmerah_crowd_areas.geojson'},
        'users': [{'id': 'crowd_001', 'weight': 1.2, 'floor': 0, 'xy': [1, 2]}],
        'areas': [{'id': 'geo_a_2', 'label': 'A-2', 'weighted_users': 7.2, 'area_m2': 45.7}],
      }), 200);
    }));
    final crowd = await api.crowdSnapshot();
    expect(crowd.userCount, 100);
    expect(crowd.totalWeight, 108.5);
    expect(crowd.data.containsKey('condition'), false);
    api.close();
  });
}
