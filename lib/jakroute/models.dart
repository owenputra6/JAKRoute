typedef Json = Map<String, dynamic>;

class RouteOption {
  final Json data;
  const RouteOption(this.data);
  String get id => data['route_id'] as String? ?? data['mode'] as String;
  String get label => data['label'] as String;
  String get mode => data['mode'] as String;
  bool get available => data['status'] == 'ok';
  double get walkingMeters => (data['walking_m'] as num?)?.toDouble() ?? 0;
  double get durationSeconds => (data['duration_s'] as num?)?.toDouble() ?? 0;
  double get crowdExposure => (data['crowd_exposure'] as num?)?.toDouble() ?? 0;
  String get explanation => data['explanation'] as String? ?? data['message'] as String? ?? '';
  List<String> get warnings => (data['warnings'] as List? ?? []).cast<String>();
  List<Json> get features =>
      ((data['geometry'] as Json?)?['features'] as List? ?? [])
          .map((x) => Map<String, dynamic>.from(x as Map)).toList();
  Json get insight => Map<String, dynamic>.from(data['insight'] as Map? ?? {});
}

class CrowdSnapshot {
  final Json data;
  const CrowdSnapshot(this.data);
  String get id => data['snapshot_id'] as String? ?? '';
  bool get simulated => data['simulated'] == true;
  String get observedAt => data['observed_at'] as String? ?? '';
  int get userCount => (data['user_count'] as num?)?.toInt() ?? 0;
  double get totalWeight => (data['total_weight'] as num?)?.toDouble() ?? 0;
  Json get source => Map<String, dynamic>.from(data['source'] as Map? ?? {});
  List<Json> get users => (data['users'] as List? ?? [])
      .map((x) => Map<String, dynamic>.from(x as Map)).toList();
  List<Json> get areas => (data['areas'] as List? ?? [])
      .map((x) => Map<String, dynamic>.from(x as Map)).toList();
}

class Recommendation {
  final Json data;
  const Recommendation(this.data);
  String get status => data['status'] as String;
  String? get question => data['question'] as String?;
  List<RouteOption> get routes => (data['routes'] as List? ?? [])
      .map((x) => RouteOption(Map<String, dynamic>.from(x as Map))).toList();
  String? get selectedId => data['selected_route_id'] as String?;
  String get forumSummary =>
      (data['forum_summary'] as Json?)?['summary'] as String? ?? '';
  String get agentMode => data['agent_mode'] as String? ?? 'unknown';
  Json get aiInsight => Map<String, dynamic>.from(data['ai_insight'] as Map? ?? {});
  /// Backend-resolved intent (origin/destination/prefs). Client-owned
  /// conversation state: send it back on the next turn so the agent remembers.
  Json get intent => Map<String, dynamic>.from(data['intent'] as Map? ?? {});
}
