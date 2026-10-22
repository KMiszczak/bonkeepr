import 'package:flutter_test/flutter_test.dart';
import 'package:garantieheld/receipt_ocr_parser.dart';

void main() {
  group('ReceiptOcrParser', () {
    test('extracts known store, labeled comma amount, and four-digit date', () {
      final result = ReceiptOcrParser.parse('''
MediaMarkt
Kaffeemaschine
Kaufdatum 12.03.2025
Zwischensumme 799,00 EUR
SUMME 649,99 €
''');

      expect(result.storeName, 'MediaMarkt');
      expect(result.productTitle, 'Kaffeemaschine');
      expect(result.totalAmount, 649.99);
      expect(result.purchaseDate, DateTime(2025, 3, 12));
      expect(result.fullText, contains('Zwischensumme'));
    });

    test('parses grouped amount with dot thousands and comma decimals', () {
      final result = ReceiptOcrParser.parse('''
REWE Markt
EC-Karte 1.234,56 EUR
04.05.26
''');

      expect(result.totalAmount, 1234.56);
      expect(result.purchaseDate, DateTime(2026, 5, 4));
      expect(result.storeName, 'REWE');
    });

    test('returns partial data without failing when amount and date are missing', () {
      final result = ReceiptOcrParser.parse('''
IKEA
Billy Regal
Vielen Dank für Ihren Einkauf
''');

      expect(result.storeName, 'IKEA');
      expect(result.productTitle, 'Billy Regal');
      expect(result.totalAmount, isNull);
      expect(result.purchaseDate, isNull);
    });

    test('keeps the captured image path in the scan result', () {
      final result = ReceiptOcrParser.parse('REWE\nSUMME 12,99 €', imagePath: 'receipts/bon.jpg');

      expect(result.imagePath, 'receipts/bon.jpg');
      expect(result.copyWith(imagePath: 'receipts/new.jpg').imagePath, 'receipts/new.jpg');
    });
  });
}

