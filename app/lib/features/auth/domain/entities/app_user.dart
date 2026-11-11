import 'package:flutter/material.dart';

enum UserRole {
  admin('admin', 'Administrador'),
  receptionist('receptionist', 'Recepcionista'),
  therapist('therapist', 'Profesional');

  const UserRole(this.value, this.label);
  final String value;
  final String label;

  static UserRole parse(String? v) =>
      UserRole.values.firstWhere((r) => r.value == v, orElse: () => UserRole.therapist);
}

/// Usuario del staff autenticado, con su perfil y permisos derivados del rol.
/// Los permisos de UI son de conveniencia: la autorización real la aplica RLS.
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.centerId,
    required this.isActive,
    this.phone,
    this.avatarUrl,
    this.colorHex = '#7C9A92',
  });

  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String centerId;
  final bool isActive;
  final String? phone;
  final String? avatarUrl;
  final String colorHex;

  bool get isAdmin => role == UserRole.admin;
  bool get isFrontDesk => role == UserRole.admin || role == UserRole.receptionist;
  bool get isTherapist => role == UserRole.therapist;

  // Matriz de permisos (espejo de las políticas RLS)
  bool get canManageClients => isFrontDesk;
  bool get canDeleteClients => isAdmin;
  bool get canManageServices => isAdmin;
  bool get canCreateAppointments => isFrontDesk;
  bool get canCancelAppointments => isFrontDesk;
  bool get canViewClinical => isAdmin || isTherapist;
  bool get canRegisterPayments => isFrontDesk;
  bool get canViewRevenue => isFrontDesk;
  bool get canManageUsers => isAdmin;

  Color get color => Color(int.parse(colorHex.replaceFirst('#', '0xFF')));

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        email: j['email'] as String,
        fullName: j['full_name'] as String,
        role: UserRole.parse(j['role'] as String?),
        centerId: j['center_id'] as String,
        isActive: j['is_active'] as bool? ?? false,
        phone: j['phone'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        colorHex: j['color_hex'] as String? ?? '#7C9A92',
      );
}
