import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_controller.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _creating = false; // false = sign in, true = create account

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    if (_creating && _name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your name.');
      return;
    }
    if (_creating && _password.text.length < 8) {
      setState(() => _error = 'Use a password with at least 8 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authControllerProvider.notifier);
    final err = _creating
        ? await auth.register(
            _email.text.trim(),
            _password.text,
            _name.text.trim(),
          )
        : await auth.signIn(_email.text.trim(), _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err?.message;
    });
    // A new account starts with the optional setup (S03).
    if (err == null && _creating) context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: AutofillGroup(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                _creating ? 'Create account' : 'Sign in',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              if (_creating) ...[
                TextField(
                  controller: _name,
                  autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                autofillHints: [
                  _creating
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('sign-in-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_creating ? 'Create account' : 'Sign in'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _creating = !_creating;
                        _error = null;
                      }),
                child: Text(
                  _creating
                      ? 'Have an account? Sign in'
                      : 'New here? Create an account',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
