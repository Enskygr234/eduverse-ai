import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/widgets.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return Scaffold(
      body: session.hasError
          ? ErrorState(message: session.error.toString(), onRetry: () => ref.invalidate(sessionProvider))
          : const Center(child: _Logo(size: 72)),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.brand, AppColors.brandDeep]),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.55),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            const Center(child: _Logo(size: 88)),
            const SizedBox(height: Space.xl),
            Text('EduVerse AI', textAlign: TextAlign.center, style: t.headlineMedium),
            const SizedBox(height: Space.sm),
            Text(
              'Dilden programlamaya, her gün birkaç dakikada\nkendi hızında öğren.',
              textAlign: TextAlign.center,
              style: t.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            FilledButton(onPressed: () => context.push('/register'), child: const Text('Hemen başla')),
            const SizedBox(height: Space.md),
            OutlinedButton(onPressed: () => context.push('/login'), child: const Text('Zaten hesabım var')),
          ]),
        ),
      ),
    );
  }
}

/// Shared scaffold + submit handling for login and register.
class _AuthForm extends ConsumerStatefulWidget {
  const _AuthForm({required this.register});
  final bool register;

  @override
  ConsumerState<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<_AuthForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = ref.read(sessionProvider.notifier);
    try {
      if (widget.register) {
        await session.register(_email.text.trim(), _password.text, _name.text.trim());
      } else {
        await session.login(_email.text.trim(), _password.text);
      }
      // The router redirects on session change.
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(Space.xl), children: [
            Text(widget.register ? 'Profilini oluştur' : 'Tekrar hoş geldin', style: t.headlineMedium),
            const SizedBox(height: Space.xl),
            if (widget.register) ...[
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Adın'),
                validator: (v) => (v == null || v.trim().length < 2) ? 'En az 2 karakter gir' : null,
              ),
              const SizedBox(height: Space.md),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'E-posta'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '') ? null : 'Geçerli bir e-posta gir',
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              autofillHints: [widget.register ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Şifre',
                helperText: widget.register ? 'En az 8 karakter, bir harf ve bir rakam' : null,
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) {
                final value = v ?? '';
                if (!widget.register) return value.isEmpty ? 'Şifreni gir' : null;
                if (value.length < 8) return 'En az 8 karakter olmalı';
                if (!RegExp(r'[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
                  return 'En az bir harf ve bir rakam içermeli';
                }
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.lg),
              Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(Radii.sm)),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: Space.xl),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(widget.register ? 'Hesap oluştur' : 'Giriş yap'),
            ),
            const SizedBox(height: Space.md),
            TextButton(
              onPressed: () => context.pushReplacement(widget.register ? '/login' : '/register'),
              child: Text(widget.register ? 'Zaten hesabın var mı? Giriş yap' : 'Hesabın yok mu? Kayıt ol'),
            ),
          ]),
        ),
      ),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  @override
  Widget build(BuildContext context) => const _AuthForm(register: false);
}

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});
  @override
  Widget build(BuildContext context) => const _AuthForm(register: true);
}
