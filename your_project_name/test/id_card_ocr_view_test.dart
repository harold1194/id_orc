import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_project_name/View/id_card_ocr_view.dart';

void main() {
  testWidgets('shows the OCR capture instructions', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IdCardOcrScreen()));

    expect(find.text('ID Card OCR'), findsOneWidget);
    expect(
      find.text('Capture or select an ID card photo to extract text'),
      findsOneWidget,
    );
    expect(find.text('Capture ID Card'), findsOneWidget);
  });

  test('extracts first name, middle name, last name, and ID number', () {
    const sampleText = '''
      REPUBLIC OF THE PHILIPPINES
      DRIVER'S LICENSE
      NAME: JUAN DELA CRUZ
      LICENSE NO: 12345678
    ''';

    final parsed = IdCardOcrScreen.parseIdCardFields(sampleText);

    expect(parsed['firstName'], 'JUAN');
    expect(parsed['middleName'], 'DELA');
    expect(parsed['lastName'], 'CRUZ');
    expect(parsed['idNumber'], '12345678');
  });

  test('extracts fields from a Philippine-style ID card layout', () {
    const sampleText = '''
      REPUBLIC OF THE PHILIPPINES
      PHILSYS ID
      FIRST NAME: JUAN
      MIDDLE NAME: DELA
      LAST NAME: CRUZ
      ID NO: 123456789012
    ''';

    final parsed = IdCardOcrScreen.parseIdCardFields(sampleText);

    expect(parsed['firstName'], 'JUAN');
    expect(parsed['middleName'], 'DELA');
    expect(parsed['lastName'], 'CRUZ');
    expect(parsed['idNumber'], '123456789012');
  });
}
