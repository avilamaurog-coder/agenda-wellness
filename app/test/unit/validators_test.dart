import 'package:agenda_wellness/core/utils/validators.dart';
import 'package:agenda_wellness/features/clients/domain/entities/client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email('ana@spa.com'), isNull);
      expect(Validators.email('ana@'), isNotNull);
      expect(Validators.email('', optional: true), isNull);
    });

    test('password exige mayúscula, minúscula y número', () {
      expect(Validators.password('abc'), isNotNull);
      expect(Validators.password('abcdefgh'), isNotNull);
      expect(Validators.password('Abcdefg1'), isNull);
    });

    test('dni argentino 7-8 dígitos', () {
      expect(Validators.dni('30.123.456'), isNull);
      expect(Validators.dni('123'), isNotNull);
      expect(Validators.dni(''), isNull);
    });

    test('parseMoney admite formato local', () {
      expect(Validators.parseMoney('28.000'), 28000);
      expect(Validators.parseMoney('1.250,50'), 1250.5);
    });
  });

  group('Client', () {
    test('alertas de salud', () {
      const c = Client(firstName: 'Ana', lastName: 'P', allergies: 'Aceite de almendras');
      expect(c.hasHealthAlerts, isTrue);
      expect(const Client(firstName: 'Ana', lastName: 'P').hasHealthAlerts, isFalse);
    });
  });
}
