import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Punto único de acceso al cliente Supabase (facilita mocks en tests).
final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

/// Stream de cambios de sesión (login, logout, refresh, recuperación de contraseña).
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});
