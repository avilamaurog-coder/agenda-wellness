import 'dart:typed_data';

import '../../../payments/domain/payment.dart';
import '../entities/client.dart';

abstract interface class ClientRepository {
  /// Búsqueda paginada por nombre, DNI, teléfono o email.
  Future<List<Client>> search({String query = '', int page = 0, int pageSize = 30});

  Future<Client> getById(String id);
  Future<ClientStats> stats(String id);
  Future<Client> create(Client client);
  Future<Client> update(Client client);

  /// Baja lógica (conserva historial y pagos).
  Future<void> archive(String id);

  Future<List<ClinicalRecord>> clinicalRecords(String clientId);
  Future<ClinicalRecord> addClinicalRecord(ClinicalRecord record, {List<Uint8List> photos = const []});
  Future<String> signedPhotoUrl(String storagePath);

  Future<List<Payment>> payments(String clientId);

  /// Telegram: invalida el enlace anterior y genera uno nuevo.
  Future<String> regenerateTelegramCode(String clientId);
  Future<void> unlinkTelegram(String clientId);
}
