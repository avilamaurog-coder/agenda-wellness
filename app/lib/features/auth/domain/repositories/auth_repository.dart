import '../entities/app_user.dart';

abstract interface class AuthRepository {
  Future<void> signIn({required String email, required String password});

  /// Registra un usuario. El primer usuario del sistema queda como administrador;
  /// los siguientes quedan pendientes de aprobación por un administrador.
  Future<void> signUp({required String email, required String password, required String fullName, String? phone});

  Future<void> sendPasswordReset(String email);
  Future<void> updatePassword(String newPassword);
  Future<void> signOut();

  /// Perfil del usuario con sesión activa, o null si no hay sesión.
  Future<AppUser?> currentUser();

  /// Lista del staff del centro (para asignar profesionales).
  Future<List<AppUser>> staff({bool onlyTherapists = false});

  Future<void> updateUserRole(String userId, UserRole role, {required bool active});
  Future<void> inviteUser({required String email, required String fullName, required UserRole role});
}
