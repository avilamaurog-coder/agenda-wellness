import 'package:flutter/foundation.dart';

enum NotificationChannel {
  whatsapp('whatsapp', 'WhatsApp'),
  email('email', 'Email'),
  push('push', 'Push'),
  telegram('telegram', 'Telegram');

  const NotificationChannel(this.value, this.label);
  final String value;
  final String label;

  static NotificationChannel parse(String? v) =>
      NotificationChannel.values.firstWhere((c) => c.value == v, orElse: () => NotificationChannel.whatsapp);
}

@immutable
class Client {
  const Client({
    this.id,
    required this.firstName,
    required this.lastName,
    this.dni,
    this.phone,
    this.whatsapp,
    this.email,
    this.birthDate,
    this.address,
    this.observations,
    this.allergies,
    this.contraindications,
    this.internalNotes,
    this.acceptsReminders = true,
    this.preferredChannel = NotificationChannel.whatsapp,
    this.createdAt,
    this.telegramChatId,
    this.telegramUsername,
    this.telegramLinkCode,
  });

  final String? id;
  final String firstName;
  final String lastName;
  final String? dni;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final DateTime? birthDate;
  final String? address;
  final String? observations;
  final String? allergies;
  final String? contraindications;
  final String? internalNotes;
  final bool acceptsReminders;
  final NotificationChannel preferredChannel;
  final DateTime? createdAt;
  final String? telegramChatId;
  final String? telegramUsername;
  final String? telegramLinkCode;

  bool get telegramLinked => telegramChatId != null;

  String get fullName => '$firstName $lastName';

  /// Alergias o contraindicaciones cargadas → mostrar alerta visible al profesional.
  bool get hasHealthAlerts =>
      (allergies?.trim().isNotEmpty ?? false) || (contraindications?.trim().isNotEmpty ?? false);

  int? get age {
    final b = birthDate;
    if (b == null) return null;
    final now = DateTime.now();
    var a = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) a--;
    return a;
  }

  bool get birthdayThisWeek {
    final b = birthDate;
    if (b == null) return false;
    final now = DateTime.now();
    final thisYear = DateTime(now.year, b.month, b.day);
    final diff = thisYear.difference(DateTime(now.year, now.month, now.day)).inDays;
    return diff >= 0 && diff < 7;
  }

  Client copyWith({
    String? firstName,
    String? lastName,
    String? dni,
    String? phone,
    String? whatsapp,
    String? email,
    DateTime? birthDate,
    String? address,
    String? observations,
    String? allergies,
    String? contraindications,
    String? internalNotes,
    bool? acceptsReminders,
    NotificationChannel? preferredChannel,
  }) =>
      Client(
        id: id,
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        dni: dni ?? this.dni,
        phone: phone ?? this.phone,
        whatsapp: whatsapp ?? this.whatsapp,
        email: email ?? this.email,
        birthDate: birthDate ?? this.birthDate,
        address: address ?? this.address,
        observations: observations ?? this.observations,
        allergies: allergies ?? this.allergies,
        contraindications: contraindications ?? this.contraindications,
        internalNotes: internalNotes ?? this.internalNotes,
        acceptsReminders: acceptsReminders ?? this.acceptsReminders,
        preferredChannel: preferredChannel ?? this.preferredChannel,
        createdAt: createdAt,
        telegramChatId: telegramChatId,
        telegramUsername: telegramUsername,
        telegramLinkCode: telegramLinkCode,
      );
}

/// Indicadores agregados del historial del cliente (vista `client_stats`).
@immutable
class ClientStats {
  const ClientStats({
    this.attended = 0,
    this.cancelled = 0,
    this.noShows = 0,
    this.upcoming = 0,
    this.totalSpent = 0,
    this.lastVisit,
    this.nextVisit,
  });

  final int attended;
  final int cancelled;
  final int noShows;
  final int upcoming;
  final num totalSpent;
  final DateTime? lastVisit;
  final DateTime? nextVisit;

  double get attendanceRate {
    final total = attended + cancelled + noShows;
    return total == 0 ? 1 : attended / total;
  }
}

@immutable
class ClinicalRecord {
  const ClinicalRecord({
    this.id,
    required this.clientId,
    required this.recordDate,
    this.therapistId,
    this.therapistName,
    this.appointmentId,
    this.evaluation,
    this.observations,
    this.treatmentGoals,
    this.evolution,
    this.painScale,
    this.photoPaths = const [],
  });

  final String? id;
  final String clientId;
  final DateTime recordDate;
  final String? therapistId;
  final String? therapistName;
  final String? appointmentId;
  final String? evaluation;
  final String? observations;
  final String? treatmentGoals;
  final String? evolution;
  final int? painScale;
  final List<String> photoPaths;
}
