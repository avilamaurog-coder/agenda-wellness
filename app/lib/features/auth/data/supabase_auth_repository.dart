import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/failure.dart';
import '../domain/entities/app_user.dart';
import '../domain/repositories/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._db);
  final SupabaseClient _db;

  GoTrueClient get _auth => _db.auth;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw Failure.from(e);
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) => _guard(() async {
        await _auth.signInWithPassword(email: email.trim(), password: password);
        final user = await currentUser();
        if (user == null || !user.isActive) {
          await _auth.signOut();
          throw const Failure('Tu cuenta está pendiente de aprobación por un administrador.');
        }
        // La versión web es exclusiva para administradores
        if (kIsWeb && !user.isAdmin) {
          await _auth.signOut();
          throw const Failure('El acceso web es solo para administradores. Usá la app móvil.');
        }
      });

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) =>
      _guard(() => _auth.signUp(
            email: email.trim(),
            password: password,
            emailRedirectTo: Env.redirectUrl,
            data: {'full_name': fullName.trim(), if (phone != null) 'phone': phone.trim()},
          ));

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.resetPasswordForEmail(email.trim(), redirectTo: Env.redirectUrl));

  @override
  Future<void> updatePassword(String newPassword) =>
      _guard(() => _auth.updateUser(UserAttributes(password: newPassword)));

  @override
  Future<void> signOut() => _guard(() => _auth.signOut());

  @override
  Future<AppUser?> currentUser() => _guard(() async {
        final uid = _auth.currentUser?.id;
        if (uid == null) return null;
        final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
        return row == null ? null : AppUser.fromJson(row);
      });

  @override
  Future<List<AppUser>> staff({bool onlyTherapists = false}) => _guard(() async {
        var q = _db.from('profiles').select().eq('is_active', true);
        if (onlyTherapists) q = q.inFilter('role', ['therapist', 'admin']);
        final rows = await q.order('full_name');
        return rows.map(AppUser.fromJson).toList();
      });

  @override
  Future<void> updateUserRole(String userId, UserRole role, {required bool active}) => _guard(() =>
      _db.rpc<void>('admin_update_user', params: {'p_user_id': userId, 'p_role': role.value, 'p_active': active}));

  @override
  Future<void> inviteUser({required String email, required String fullName, required UserRole role}) =>
      _guard(() => _db.functions.invoke('invite-user', body: {
            'email': email.trim(),
            'full_name': fullName.trim(),
            'role': role.value,
          }));
}
