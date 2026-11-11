import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../center/data/supabase_center_repository.dart';
import '../../../center/presentation/center_logo.dart';

/// Marco visual común para las pantallas de autenticación.
class AuthLayout extends ConsumerWidget {
  const AuthLayout({super.key, required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final brand = ref.watch(publicBrandingProvider).valueOrNull;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.sage.withValues(alpha: 0.22), t.colorScheme.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: CenterLogo(url: brand?.logoUrl, size: 84)),
                    if (brand != null) ...[
                      const SizedBox(height: 10),
                      Text(brand.name, textAlign: TextAlign.center, style: t.textTheme.titleMedium),
                    ],
                    const SizedBox(height: 24),
                    Text(title, textAlign: TextAlign.center, style: t.textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 32),
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
