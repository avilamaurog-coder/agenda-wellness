import '../domain/entities/client.dart';

/// Conversión entre filas de PostgreSQL y entidades de dominio.
/// Se mantiene fuera del dominio para que las entidades no dependan del backend.
abstract final class ClientMapper {
  static Client fromRow(Map<String, dynamic> j) => Client(
        id: j['id'] as String,
        firstName: j['first_name'] as String,
        lastName: j['last_name'] as String,
        dni: j['dni'] as String?,
        phone: j['phone'] as String?,
        whatsapp: j['whatsapp'] as String?,
        email: j['email'] as String?,
        birthDate: DateTime.tryParse(j['birth_date'] as String? ?? ''),
        address: j['address'] as String?,
        observations: j['observations'] as String?,
        allergies: j['allergies'] as String?,
        contraindications: j['contraindications'] as String?,
        internalNotes: j['internal_notes'] as String?,
        acceptsReminders: j['accepts_reminders'] as bool? ?? true,
        preferredChannel: NotificationChannel.parse(j['preferred_channel'] as String?),
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
        telegramChatId: j['telegram_chat_id'] as String?,
        telegramUsername: j['telegram_username'] as String?,
        telegramLinkCode: j['telegram_link_code'] as String?,
      );

  static Map<String, dynamic> toRow(Client c) {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    return {
      'first_name': c.firstName.trim(),
      'last_name': c.lastName.trim(),
      'dni': clean(c.dni)?.replaceAll(RegExp(r'\D'), ''),
      'phone': clean(c.phone),
      'whatsapp': clean(c.whatsapp),
      'email': clean(c.email)?.toLowerCase(),
      'birth_date': c.birthDate?.toIso8601String().substring(0, 10),
      'address': clean(c.address),
      'observations': clean(c.observations),
      'allergies': clean(c.allergies),
      'contraindications': clean(c.contraindications),
      'internal_notes': clean(c.internalNotes),
      'accepts_reminders': c.acceptsReminders,
      'preferred_channel': c.preferredChannel.value,
    };
  }

  static ClientStats statsFromRow(Map<String, dynamic>? j) {
    if (j == null) return const ClientStats();
    return ClientStats(
      attended: (j['attended'] as num?)?.toInt() ?? 0,
      cancelled: (j['cancelled'] as num?)?.toInt() ?? 0,
      noShows: (j['no_shows'] as num?)?.toInt() ?? 0,
      upcoming: (j['upcoming'] as num?)?.toInt() ?? 0,
      totalSpent: j['total_spent'] as num? ?? 0,
      lastVisit: DateTime.tryParse(j['last_visit'] as String? ?? ''),
      nextVisit: DateTime.tryParse(j['next_visit'] as String? ?? ''),
    );
  }

  static ClinicalRecord recordFromRow(Map<String, dynamic> j) => ClinicalRecord(
        id: j['id'] as String,
        clientId: j['client_id'] as String,
        appointmentId: j['appointment_id'] as String?,
        therapistId: j['therapist_id'] as String?,
        therapistName: (j['therapist'] as Map<String, dynamic>?)?['full_name'] as String?,
        recordDate: DateTime.parse(j['record_date'] as String),
        evaluation: j['evaluation'] as String?,
        observations: j['observations'] as String?,
        treatmentGoals: j['treatment_goals'] as String?,
        evolution: j['evolution'] as String?,
        painScale: (j['pain_scale'] as num?)?.toInt(),
        photoPaths: ((j['clinical_photos'] as List<dynamic>?) ?? const [])
            .map((p) => (p as Map<String, dynamic>)['storage_path'] as String)
            .toList(),
      );
}
