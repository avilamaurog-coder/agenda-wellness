import 'package:flutter/foundation.dart';

/// Datos del centro: identidad de marca, contacto y configuración de integraciones.
@immutable
class BusinessCenter {
  const BusinessCenter({
    required this.id,
    required this.name,
    this.legalName,
    this.cuit,
    this.description,
    this.phone,
    this.email,
    this.address,
    this.whatsappContact,
    this.instagram,
    this.website,
    this.logoUrl,
    this.publicCatalogEnabled = true,
    this.telegramBotUsername,
    this.telegramAdminChatId,
    this.telegramChannelId,
    this.backupEnabled = true,
  });

  final String id;
  final String name;
  final String? legalName;
  final String? cuit;
  final String? description;
  final String? phone;
  final String? email;
  final String? address;
  final String? whatsappContact;
  final String? instagram;
  final String? website;
  final String? logoUrl;
  final bool publicCatalogEnabled;
  final String? telegramBotUsername;
  final String? telegramAdminChatId;
  final String? telegramChannelId;
  final bool backupEnabled;

  bool get telegramConfigured => (telegramBotUsername ?? '').isNotEmpty;

  /// Enlace de vinculación para un cliente: `t.me/<bot>?start=<código>`
  String? telegramLinkFor(String code) =>
      telegramConfigured ? 'https://t.me/${telegramBotUsername!.replaceAll('@', '')}?start=$code' : null;

  factory BusinessCenter.fromJson(Map<String, dynamic> j) => BusinessCenter(
        id: j['id'] as String,
        name: j['name'] as String,
        legalName: j['legal_name'] as String?,
        cuit: j['cuit'] as String?,
        description: j['description'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        address: j['address'] as String?,
        whatsappContact: j['whatsapp_contact'] as String? ?? j['whatsapp'] as String?,
        instagram: j['instagram'] as String?,
        website: j['website'] as String?,
        logoUrl: j['logo_url'] as String?,
        publicCatalogEnabled: j['public_catalog_enabled'] as bool? ?? true,
        telegramBotUsername: j['telegram_bot_username'] as String? ?? j['telegram_bot'] as String?,
        telegramAdminChatId: j['telegram_admin_chat_id'] as String?,
        telegramChannelId: j['telegram_channel_id'] as String?,
        backupEnabled: j['backup_enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toRow() {
    String? c(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    return {
      'name': name.trim(),
      'legal_name': c(legalName),
      'cuit': c(cuit),
      'description': c(description),
      'phone': c(phone),
      'email': c(email),
      'address': c(address),
      'whatsapp_contact': c(whatsappContact),
      'instagram': c(instagram)?.replaceAll('@', ''),
      'website': c(website),
      'logo_url': logoUrl,
      'public_catalog_enabled': publicCatalogEnabled,
      'telegram_bot_username': c(telegramBotUsername)?.replaceAll('@', ''),
      'telegram_admin_chat_id': c(telegramAdminChatId),
      'telegram_channel_id': c(telegramChannelId),
      'backup_enabled': backupEnabled,
    };
  }
}

@immutable
class BackupRecord {
  const BackupRecord({
    required this.id,
    required this.provider,
    required this.trigger,
    required this.status,
    required this.startedAt,
    this.fileName,
    this.sizeBytes,
    this.encrypted = false,
    this.error,
    this.finishedAt,
  });

  final String id;
  final String provider;
  final String trigger;
  final String status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? fileName;
  final int? sizeBytes;
  final bool encrypted;
  final String? error;

  String get providerLabel => provider == 'onedrive' ? 'OneDrive' : 'Google Drive';

  factory BackupRecord.fromJson(Map<String, dynamic> j) => BackupRecord(
        id: j['id'] as String,
        provider: j['provider'] as String,
        trigger: j['trigger'] as String,
        status: j['status'] as String,
        startedAt: DateTime.parse(j['started_at'] as String).toLocal(),
        finishedAt: DateTime.tryParse(j['finished_at'] as String? ?? '')?.toLocal(),
        fileName: j['file_name'] as String?,
        sizeBytes: (j['size_bytes'] as num?)?.toInt(),
        encrypted: j['encrypted'] as bool? ?? false,
        error: j['error'] as String?,
      );
}

abstract interface class CenterRepository {
  Future<BusinessCenter> current();
  Future<BusinessCenter> update(BusinessCenter center);
  Future<String> uploadLogo(String centerId, Uint8List bytes, String extension);

  /// Marca pública (sin sesión): nombre y logo para la pantalla de login.
  Future<BusinessCenter?> publicBranding();

  Future<List<BackupRecord>> backups();
  Future<void> runBackupNow();
}
