import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../auth_providers.dart';
import 'auth_layout.dart';

/// Paso 1: solicitar el enlace de recuperación.
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await ref.read(authControllerProvider.notifier).sendReset(_email.text);
    if (!mounted) return;
    if (ok) {
      setState(() => _sent = true);
    } else {
      context.showError(ref.read(authControllerProvider).error ?? const Failure('Error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authControllerProvider).isLoading;
    return AuthLayout(
      title: 'Recuperar contraseña',
      subtitle: _sent
          ? 'Si el email está registrado, vas a recibir un enlace para crear una nueva contraseña.'
          : 'Ingresá tu email y te enviaremos un enlace.',
      child: _sent
          ? FilledButton(onPressed: () => context.go('/auth/login'), child: const Text('Volver al inicio'))
          : Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                    validator: Validators.email,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: loading ? null : _submit, child: const Text('Enviar enlace')),
                  TextButton(onPressed: () => context.pop(), child: const Text('Cancelar')),
                ],
              ),
            ),
    );
  }
}

/// Paso 2: se abre desde el deep link (evento AuthChangeEvent.passwordRecovery).
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final ok = await ref.read(authControllerProvider.notifier).updatePassword(_password.text);
    if (!mounted) return;
    if (ok) {
      context.showSnack('Contraseña actualizada');
      context.go('/');
    } else {
      context.showError(ref.read(authControllerProvider).error ?? const Failure('Error'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Nueva contraseña',
      subtitle: 'Elegí una contraseña segura',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nueva contraseña', prefixIcon: Icon(Icons.lock_outline)),
              validator: Validators.password,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _submit, child: const Text('Guardar')),
          ],
        ),
      ),
    );
  }
}
