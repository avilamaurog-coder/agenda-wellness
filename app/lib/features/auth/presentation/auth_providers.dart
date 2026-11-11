import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_providers.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);

/// Usuario actual. Se recalcula ante cada evento de autenticación.
final currentUserProvider = FutureProvider<AppUser?>((ref) async {
  ref.watch(authStateChangesProvider);
  return ref.watch(authRepositoryProvider).currentUser();
});

/// Atajo síncrono para widgets que ya están detrás del guard de autenticación.
final sessionUserProvider = Provider<AppUser>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) throw StateError('sessionUserProvider usado sin sesión activa');
  return user;
});

final therapistsProvider = FutureProvider<List<AppUser>>(
  (ref) => ref.watch(authRepositoryProvider).staff(onlyTherapists: true),
);

final staffProvider = FutureProvider<List<AppUser>>(
  (ref) => ref.watch(authRepositoryProvider).staff(),
);

/// Controlador de acciones de autenticación (login, registro, recuperación).
class AuthController extends AutoDisposeAsyncNotifier<void> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<void> build() async {}

  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    return !state.hasError;
  }

  Future<bool> signIn(String email, String password) =>
      _run(() => _repo.signIn(email: email, password: password));

  Future<bool> signUp({required String email, required String password, required String fullName, String? phone}) =>
      _run(() => _repo.signUp(email: email, password: password, fullName: fullName, phone: phone));

  Future<bool> sendReset(String email) => _run(() => _repo.sendPasswordReset(email));

  Future<bool> updatePassword(String password) => _run(() => _repo.updatePassword(password));

  Future<void> signOut() => _run(_repo.signOut);
}

final authControllerProvider = AsyncNotifierProvider.autoDispose<AuthController, void>(AuthController.new);
