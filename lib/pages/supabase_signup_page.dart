import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/socket_service.dart';

class SupabaseSignUpPage extends StatefulWidget {
  final SocketService socketService;

  const SupabaseSignUpPage({
    super.key,
    required this.socketService,
  });

  @override
  State<SupabaseSignUpPage> createState() => _SupabaseSignUpPageState();
}

class _SupabaseSignUpPageState extends State<SupabaseSignUpPage> {
  final Logger _logger = Logger();
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String _status = '';

  @override
  void dispose() {
    _userNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final userName = _userNameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (userName.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _status = 'Enter user name, email and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Creating account...';
    });

    try {
      final supabase = Supabase.instance.client;

      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'user_name': userName,
        },
      );

      if (!mounted) return;
      // Return to sign-in page. If email confirmations are enabled, the user
      // may need to confirm email before sign-in succeeds.
      Navigator.pop(context, email);
    } on AuthException catch (e) {
      _logger.w('Supabase sign-up error: ${e.message}');
      setState(() => _status = e.message);
    } catch (e) {
      _logger.e('Unexpected sign-up error: $e');
      setState(() => _status = 'Sign-up failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Supabase Sign Up'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _userNameController,
              enabled: !_isLoading,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'User name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              enabled: !_isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              enabled: !_isLoading,
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create Account'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isLoading ? null : () => Navigator.pop(context),
              child: const Text('Already have an account? Sign in'),
            ),
            const SizedBox(height: 12),
            if (_status.isNotEmpty)
              Text(
                _status,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
