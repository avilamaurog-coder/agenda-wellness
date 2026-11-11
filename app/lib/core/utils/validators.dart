abstract final class Validators {
  static String? required(String? v, [String field = 'Este campo']) =>
      (v == null || v.trim().isEmpty) ? '$field es obligatorio' : null;

  static String? email(String? v, {bool optional = false}) {
    if (v == null || v.trim().isEmpty) return optional ? null : 'Ingresá un email';
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : 'Email inválido';
  }

  static String? password(String? v) {
    if (v == null || v.length < 8) return 'Mínimo 8 caracteres';
    if (!RegExp(r'[A-Z]').hasMatch(v) || !RegExp(r'[a-z]').hasMatch(v)) {
      return 'Usá mayúsculas y minúsculas';
    }
    if (!RegExp(r'\d').hasMatch(v)) return 'Incluí al menos un número';
    return null;
  }

  static String? dni(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final d = v.replaceAll(RegExp(r'\D'), '');
    return (d.length >= 7 && d.length <= 8) ? null : 'DNI inválido (7 u 8 dígitos)';
  }

  static String? phone(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final d = v.replaceAll(RegExp(r'\D'), '');
    return d.length >= 8 ? null : 'Teléfono inválido';
  }

  static String? positiveNumber(String? v, [String field = 'El valor']) {
    final n = num.tryParse((v ?? '').replaceAll('.', '').replaceAll(',', '.'));
    if (n == null) return '$field debe ser numérico';
    if (n < 0) return '$field no puede ser negativo';
    return null;
  }

  /// Convierte "28.000,50" o "28000" a num.
  static num? parseMoney(String? v) =>
      num.tryParse((v ?? '').trim().replaceAll('.', '').replaceAll(',', '.'));
}
