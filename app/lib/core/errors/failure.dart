import 'package:supabase_flutter/supabase_flutter.dart';

/// Error de dominio con mensaje apto para mostrar al usuario.
class Failure implements Exception {
  const Failure(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  /// Traduce errores de Supabase/PostgREST/Postgres a mensajes comprensibles.
  factory Failure.from(Object error) {
    if (error is Failure) return error;
    if (error is AuthException) {
      return Failure(_authMessage(error), code: error.statusCode, cause: error);
    }
    if (error is PostgrestException) {
      return Failure(_pgMessage(error), code: error.code, cause: error);
    }
    if (error is StorageException) {
      return Failure('No se pudo subir el archivo: ${error.message}', cause: error);
    }
    final text = error.toString();
    if (text.contains('SocketException') || text.contains('ClientException')) {
      return Failure('Sin conexión. Revisá tu internet e intentá de nuevo.', cause: error);
    }
    return Failure('Ocurrió un error inesperado.', cause: error);
  }

  static String _authMessage(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'Email o contraseña incorrectos.';
    if (m.contains('email not confirmed')) return 'Confirmá tu email antes de ingresar.';
    if (m.contains('already registered')) return 'Ya existe una cuenta con ese email.';
    if (m.contains('password')) return 'La contraseña no cumple los requisitos de seguridad.';
    if (m.contains('rate limit')) return 'Demasiados intentos. Esperá unos minutos.';
    return e.message;
  }

  static String _pgMessage(PostgrestException e) {
    switch (e.code) {
      case '23P01': // exclusion_violation
      case 'P0409':
        return 'El profesional ya tiene un turno en ese horario.';
      case '23505':
        if (e.message.contains('dni')) return 'Ya existe un cliente con ese DNI.';
        return 'El registro ya existe.';
      case '23503':
        return 'No se puede completar: hay datos relacionados.';
      case '42501':
        return 'No tenés permisos para realizar esta acción.';
      case 'P0001': // raise exception desde PL/pgSQL
        return e.message;
      default:
        return e.message;
    }
  }

  @override
  String toString() => 'Failure($code): $message';
}
