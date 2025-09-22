import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/providers.dart';
import '../../data/models/app_user.dart';
import '../../theme/tokens.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();
  final _signupEmail = TextEditingController();
  final _signupPassword = TextEditingController();
  AppRole _signupRole = AppRole.resident;
  final _signupPgy = TextEditingController();
  bool _obscureLogin = true;
  bool _obscureSignup = true;
  String? _error;
  bool _loading = false;

  Future<void> _handleLogin() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(email: _loginEmail.text.trim(), password: _loginPassword.text);
    } on fb_auth.FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleSignup() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cred = await ref.read(firebaseAuthProvider).createUserWithEmailAndPassword(email: _signupEmail.text.trim(), password: _signupPassword.text);
      final uid = cred.user!.uid;
      final repo = ref.read(usersRepoProvider);
      final user = AppUser(uid: uid, role: _signupRole, email: _signupEmail.text.trim(), pgy: int.tryParse(_signupPgy.text));
      await repo.createOrUpdate(user);
    } on fb_auth.FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.surfaceVariant,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  const SizedBox(height: 56),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('AHN', style: theme.textTheme.titleLarge),
                      const Text('A Partnership with US Acute Care Solutions'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Bridge/EKG Illustration'),
                  ),
                  const SizedBox(height: 24),
                  TabBar(
                    controller: _tab,
                    labelColor: AppColors.teal600,
                    unselectedLabelColor: AppColors.textSecondary,
                    indicator: const UnderlineTabIndicator(borderSide: BorderSide(color: AppColors.teal600, width: 3)),
                    tabs: const [Tab(text: 'Login'), Tab(text: 'Sign up')],
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                  ],
                  AnimatedBuilder(
                    animation: _tab,
                    builder: (context, _) {
                      return _tab.index == 0 ? _buildLoginCard() : _buildSignupCard();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginCard() {
    final valid = _loginEmail.text.contains('@') && _loginPassword.text.length >= 8;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _loginEmail, decoration: const InputDecoration(labelText: 'Email'), onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            TextField(
              controller: _loginPassword,
              obscureText: _obscureLogin,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(_obscureLogin ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureLogin = !_obscureLogin),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading || !valid ? null : _handleLogin,
                child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Login'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(email: _loginEmail.text.trim()), child: const Text('Forgot password?')),
          ],
        ),
      ),
    );
  }

  Widget _buildSignupCard() {
    final validEmail = _signupEmail.text.contains('@');
    final validPass = _signupPassword.text.length >= 8;
    final valid = validEmail && validPass && (_signupRole != AppRole.resident || int.tryParse(_signupPgy.text) != null);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            DropdownButtonFormField<AppRole>(
              value: _signupRole,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: AppRole.resident, child: Text('Resident')),
                DropdownMenuItem(value: AppRole.attending, child: Text('Attending')),
                DropdownMenuItem(value: AppRole.admin, child: Text('Admin')),
              ],
              onChanged: (r) => setState(() => _signupRole = r ?? AppRole.resident),
            ),
            const SizedBox(height: 12),
            if (_signupRole == AppRole.resident) ...[
              TextField(controller: _signupPgy, decoration: const InputDecoration(labelText: 'PGY (1-5)')),
              const SizedBox(height: 12),
            ],
            TextField(controller: _signupEmail, decoration: const InputDecoration(labelText: 'Email'), onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
            TextField(
              controller: _signupPassword,
              obscureText: _obscureSignup,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Password (min 8 chars)',
                suffixIcon: IconButton(
                  icon: Icon(_obscureSignup ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureSignup = !_obscureSignup),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading || !valid ? null : _handleSignup,
                child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign up'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
