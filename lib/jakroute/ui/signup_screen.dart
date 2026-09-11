import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api_client.dart';
import 'app_shell.dart';
import 'app_theme.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.api, required this.mapStyleUrl});

  final JakRouteApi api;
  final String mapStyleUrl;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _info;

  Future<void> _signup() async {
    setState(() { _loading = true; _error = null; _info = null; });
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      if (res.session != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => AppShell(api: widget.api, mapStyleUrl: widget.mapStyleUrl)),
        );
      } else {
        setState(() => _info = 'Akun dibuat. Cek email untuk konfirmasi, lalu masuk.');
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Pendaftaran gagal. Coba lagi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: Space.xl),
              Text('Daftar', style: Theme.of(context).textTheme.displayLarge),
              const SizedBox(height: Space.lg),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: Space.sm),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password (min 6 karakter)'),
              ),
              if (_error != null) ...[
                const SizedBox(height: Space.sm),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              if (_info != null) ...[
                const SizedBox(height: Space.sm),
                Text(_info!, style: const TextStyle(color: AppColors.success)),
              ],
              const SizedBox(height: Space.lg),
              FilledButton(
                onPressed: _loading ? null : _signup,
                child: _loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Daftar'),
              ),
              const SizedBox(height: Space.xs),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Sudah punya akun? Masuk'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
