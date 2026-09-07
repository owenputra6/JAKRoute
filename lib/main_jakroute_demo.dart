import 'package:flutter/material.dart';
import 'jakroute/jakroute.dart';

void main() => runApp(const JakRouteDemoApp());

class JakRouteDemoApp extends StatefulWidget {
  const JakRouteDemoApp({super.key});
  @override
  State<JakRouteDemoApp> createState() => _JakRouteDemoAppState();
}

class _JakRouteDemoAppState extends State<JakRouteDemoApp> {
  late final JakRouteApi api;
  @override
  void initState() {
    super.initState();
    api = JakRouteApi(baseUrl: const String.fromEnvironment('BACKEND_URL', defaultValue: 'http://10.0.2.2:8000'));
  }
  @override
  void dispose() { api.close(); super.dispose(); }
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'JAKRoute Demo', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176bdf)), useMaterial3: true),
    home: JakRouteScreen(api: api, mapStyleUrl: const String.fromEnvironment('MAPID_STYLE_URL')),
  );
}
