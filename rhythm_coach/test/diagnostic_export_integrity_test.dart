import 'package:beat_bitch/services/diagnostic_export_integrity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticExportIntegrity.canonicalJson', () {
    test('trie les clés à toute profondeur', () {
      final out = DiagnosticExportIntegrity.canonicalJson({
        'b': 1,
        'a': {'z': 2, 'y': 3},
      });
      expect(out, '{"a":{"y":3,"z":2},"b":1}');
    });

    test('insensible à l\'ordre d\'insertion source (même hash)', () {
      final p1 = <String, dynamic>{'a': 1, 'b': 2};
      final p2 = <String, dynamic>{'b': 2, 'a': 1};
      expect(DiagnosticExportIntegrity.compute(p1),
          DiagnosticExportIntegrity.compute(p2));
    });

    test('listes : ordre préservé (sémantique)', () {
      final out = DiagnosticExportIntegrity.canonicalJson([3, 1, 2]);
      expect(out, '[3,1,2]');
    });

    test('null / nombres / strings encodés JSON standard', () {
      expect(DiagnosticExportIntegrity.canonicalJson(null), 'null');
      expect(DiagnosticExportIntegrity.canonicalJson(42), '42');
      expect(DiagnosticExportIntegrity.canonicalJson('hi'), '"hi"');
      expect(DiagnosticExportIntegrity.canonicalJson(true), 'true');
    });
  });

  group('DiagnosticExportIntegrity.verify', () {
    Map<String, dynamic> signed(Map<String, dynamic> data) {
      final out = Map<String, dynamic>.from(data);
      out['integrity'] = <String, dynamic>{
        'algorithm': DiagnosticExportIntegrity.algorithm,
        'value': DiagnosticExportIntegrity.compute(data),
        'scope': 'test',
      };
      return out;
    }

    test('accepte un payload bien signé', () {
      final p = signed({'a': 1, 'b': 'x'});
      expect(DiagnosticExportIntegrity.verify(p), isTrue);
    });

    test('rejette quand `integrity` manque', () {
      expect(
          DiagnosticExportIntegrity.verify(<String, dynamic>{'a': 1}), isFalse);
    });

    test('rejette quand algorithm n\'est pas sha256', () {
      final p = signed({'a': 1});
      (p['integrity'] as Map<String, dynamic>)['algorithm'] = 'crc32';
      expect(DiagnosticExportIntegrity.verify(p), isFalse);
    });
  });
}
