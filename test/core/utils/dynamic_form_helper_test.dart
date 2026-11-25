import 'package:flutter_test/flutter_test.dart';
import 'package:halo_apu_mobile/core/utils/dynamic_form_helper.dart';

void main() {
  group('DynamicFormHelper', () {
    final fields = <Map<String, dynamic>>[
      {
        'id': '10',
        'label': 'Pilih Alat',
        'type': 'multi_pilih',
        'options': ['Infokus', 'Kabel HDMI', 'Yang lain:'],
        'parent_field_id': null,
        'trigger_value': null,
      },
      {
        'id': '20',
        'label': 'Tanggal Pinjam',
        'type': 'tanggal',
        'parent_field_id': null,
        'trigger_value': null,
      },
      {
        'id': '11',
        'label': 'Sebutkan Alat Lainnya',
        'type': 'teks_pendek',
        'parent_field_id': '10',
        'trigger_value': 'Yang lain:',
      },
      {
        'id': '12',
        'label': 'Catatan Khusus HDMI',
        'type': 'teks_pendek',
        'parent_field_id': '10',
        'trigger_value': 'kabel hdmi',
      },
      {
        'id': '13',
        'label': 'Detail Tambahan',
        'type': 'teks_pendek',
        'parent_field_id': '11',
        'trigger_value': 'Mic',
      },
    ];

    test('multi_pilih menampilkan field cabang ketika opsi pemicu dipilih', () {
      final formData = <String, dynamic>{
        '10': ['Infokus'],
      };

      expect(DynamicFormHelper.isFieldVisible(fields[2], formData, fields), isFalse);
      expect(DynamicFormHelper.isFieldVisible(fields[3], formData, fields), isFalse);

      formData['10'] = <dynamic>['Infokus', 'Yang lain:'];
      expect(DynamicFormHelper.isFieldVisible(fields[2], formData, fields), isTrue);
      expect(DynamicFormHelper.isFieldVisible(fields[3], formData, fields), isFalse);

      formData['10'] = <String>['Kabel HDMI', 'Yang lain:'];
      expect(DynamicFormHelper.isFieldVisible(fields[2], formData, fields), isTrue);
      expect(DynamicFormHelper.isFieldVisible(fields[3], formData, fields), isTrue);
    });

    test('normalisasi mengabaikan titik dua dan huruf besar/kecil', () {
      final branchWithNoColon = {
        'id': '15',
        'label': 'Lainnya',
        'parent_field_id': '10',
        'trigger_value': 'yang lain',
      };
      final formData = <String, dynamic>{
        '10': ['Yang Lain:'],
      };

      expect(DynamicFormHelper.isFieldVisible(branchWithNoColon, formData, fields), isTrue);
    });

    test('menyembunyikan cabang bertingkat jika induk tidak dipilih lagi', () {
      final formData = <String, dynamic>{
        '10': ['Infokus'],
        '11': 'Mic',
      };

      expect(DynamicFormHelper.isFieldVisible(fields[4], formData, fields), isFalse);

      formData['10'] = ['Infokus', 'Yang lain:'];
      expect(DynamicFormHelper.isFieldVisible(fields[4], formData, fields), isTrue);
    });

    test('orderFieldsTree menempatkan cabang tepat di bawah parent', () {
      final ordered = DynamicFormHelper.orderFieldsTree(fields);
      expect(ordered.map((f) => f['id']).toList(), ['10', '11', '13', '12', '20']);
    });
  });
}
