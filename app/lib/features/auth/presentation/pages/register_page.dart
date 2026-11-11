import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../auth_providers.dart';
import 'auth_layout.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await ref.read(authControllerProvider.notifier).signUp(
          email: _email.text,
          password: _password.text,
          fullName: _name.text,
          phone: _phone.text.isEmpty ? null : _phone.text,
        );
    if (!mounted) return;
    if (!ok) {
      context.showError(ref.read(authControllerProvider).error ?? const Failure('Error'));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.mark_email_read_outlined, size: 40),
        title: const Text('Revisá tu correo'),
        content: const Text(
          'Te enviamos un enlace para confirmar tu cuenta. '
          'Si no sos el primer usuario del centro, un administrador deberá habilitar tu acceso.',
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
      ),
    );
    if (mounted) context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider).isLoading;
    const gap = SizedBox(height: 14);

    return AuthLayout(
      title: 'Crear cuenta',
      subtitle: 'Registrate para acceder al sistema',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre y apellido', prefixIcon: Icon(Icons.person_outline)),
              validator: (v) => Validators.required(v, 'El nombre'),
            ),
            gap,
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
              validator: Validators.email,
            ),
            gap,
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono (opcional)', prefixIcon: Icon(Icons.phone_outlined)),
              validator: Validators.phone,
            ),
            gap,
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                helperText: 'Mínimo 8 caracteres, mayúsculas, minúsculas y un número',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              validator: Validators.password,
            ),
            gap,
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repetir contraseña', prefixIcon: Icon(Icons.lock_outline)),
              validator: (v) => v != _password.text ? 'Las contraseñas no coinciden' : null,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: loading ? null : _submit,
              child: loading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Crear cuenta'),
            ),
            TextButton(onPressed: () => context.pop(), child: const Text('Ya tengo cuenta')),
          ],
        ),
      ),
    );
  }
}
