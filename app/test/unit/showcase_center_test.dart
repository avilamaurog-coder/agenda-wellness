import 'package:agenda_wellness/features/center/domain/center.dart';
import 'package:agenda_wellness/features/showcase/domain/showcase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BusinessCenter', () {
    test('arma el enlace de vinculación de Telegram', () {
      const c = BusinessCenter(id: '1', name: 'Spa', telegramBotUsername: '@AgendaWellnessBot');
      expect(c.telegramLinkFor('abc123'), 'https://t.me/AgendaWellnessBot?start=abc123');
    });

    test('sin bot configurado no hay enlace', () {
      const c = BusinessCenter(id: '1', name: 'Spa');
      expect(c.telegramLinkFor('abc'), isNull);
    });
  });

  group('Vitrina', () {
    test('producto sin control de stock siempre disponible', () {
      expect(const Product(name: 'Gift card', price: 25000).inStock, isTrue);
      expect(const Product(name: 'Aceite', price: 12000, stock: 0).inStock, isFalse);
    });

    test('promoción vigente según fechas', () {
      final today = DateTime.now();
      final live = PromoPost(title: 'A', startsOn: today.subtract(const Duration(days: 1)));
      final expired = PromoPost(
        title: 'B',
        startsOn: today.subtract(const Duration(days: 10)),
        endsOn: today.subtract(const Duration(days: 2)),
      );
      final paused = PromoPost(title: 'C', startsOn: today, isActive: false);
      expect(live.isLive, isTrue);
      expect(expired.isLive, isFalse);
      expect(paused.isLive, isFalse);
    });
  });
}
