import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'jakroute/api_client.dart';
import 'jakroute/ui/app_shell.dart';
import 'jakroute/ui/app_theme.dart';
import 'jakroute/ui/mobile_frame.dart';

const _backendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'https://jakroute-api-production.up.railway.app',
);
const _mapStyleUrl = String.fromEnvironment('MAPID_STYLE_URL');
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
    if (Supabase.instance.client.auth.currentSession == null) {
      // Guest access: no signup friction for judges/first-time users.
      // Must not crash boot if anonymous sign-in is disabled on the project.
      try {
        await Supabase.instance.client.auth.signInAnonymously();
      } catch (_) {
        // Falls back to unauthenticated requests; AUTH_MODE=demo accepts them.
      }
    }
  }
  runApp(const JakRouteApp());
}

class JakRouteApp extends StatefulWidget {
  const JakRouteApp({super.key});

  @override
  State<JakRouteApp> createState() => _JakRouteAppState();
}

class _JakRouteAppState extends State<JakRouteApp> {
  late final JakRouteApi api;

  @override
  void initState() {
    super.initState();
    api = JakRouteApi(
      baseUrl: _backendUrl,
      accessToken: _supabaseUrl.isEmpty
          ? null
          : () async => Supabase.instance.client.auth.currentSession?.accessToken,
    );
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JAKRoute',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, child) => MobileFrame(child: child ?? const SizedBox.shrink()),
      home: AppShell(api: api, mapStyleUrl: _mapStyleUrl),
    );
  }
}
