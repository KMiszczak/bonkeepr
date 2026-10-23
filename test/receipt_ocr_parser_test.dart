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

    test('does not mistake a street address or postal code for the store', () {
      final result = ReceiptOcrParser.parse('''
Clausewitzstraße 3
10115 Berlin
Mein Fachgeschäft
Kaufdatum 12.03.2025
''');

      expect(result.storeName, 'Mein Fachgeschäft');
    });

    test('recognizes additional known merchants in the first receipt lines', () {
      for (final store in [
        'ALDI SÜD',
        'A L DI',
        'LIDL',
        'EDEKA',
        'BAUHAUS',
        'H&M',
        'KAUFLAND',
        'ACTION',
      ]) {
        final result = ReceiptOcrParser.parse('$store\nArtikel 3,99 €');
        expect(result.storeName, store.startsWith('ALDI') || store == 'A L DI' ? 'ALDI' : store);
      }
    });

    test('extracts the first product price from the same line, not the total', () {
      final result = ReceiptOcrParser.parse('''
REWE
MOBILE ENERGIESTATION 29,99 € 2
SUMME 35,65 €
''');

      expect(result.productTitle, 'MOBILE ENERGIESTATION');
      expect(result.productPrice, 29.99);
      expect(result.totalAmount, 35.65);
    });

    test('extracts a product price from the direct next line', () {
      final result = ReceiptOcrParser.parse('''
REWE
Espressomaschine
129.50 €
SUMME 149,50 €
''');

      expect(result.productTitle, 'Espressomaschine');
      expect(result.productPrice, 129.50);
      expect(result.totalAmount, 149.50);
    });

    test('extracts next-line price when the price row also contains a quantity', () {
      final result = ReceiptOcrParser.parse('''
REWE
MOBILE ENERGIESTATION
1 x 29,99 €
SUMME 29,99 €
''');

      expect(result.productTitle, 'MOBILE ENERGIESTATION');
      expect(result.productPrice, 29.99);
    });

    test('does not use total or payment lines as the product price', () {
      final result = ReceiptOcrParser.parse('''
REWE
Kaffeemaschine
BAR 99,99 €
EC-KARTE 99,99 €
GEGEBEN 100,00 €
RÜCKGELD 0,01 €
SUMME 99,99 €
''');

      expect(result.productTitle, 'Kaffeemaschine');
      expect(result.productPrice, isNull);
      expect(result.totalAmount, 99.99);
    });

    test('falls back to the amount on a ZU ZAHLEN line', () {
      final result = ReceiptOcrParser.parse('''
REWE
Kaffeemaschine
ZU ZAHLEN 79,99 €
''');

      expect(result.productTitle, 'Kaffeemaschine');
      expect(result.productPrice, 79.99);
    });

    test('falls back to an EUR amount when the product line has no price', () {
      final result = ReceiptOcrParser.parse('''
REWE
Kaffeemaschine
Kaufdatum 12.03.2025
EUR 79,99
''');

      expect(result.productTitle, 'Kaffeemaschine');
      expect(result.productPrice, 79.99);
    });

    test('does not put a product title into the merchant field', () {
      final result = ReceiptOcrParser.parse('''
Spezialprodukt 29,99 €
SUMME 29,99 €
''');

      expect(result.productTitle, 'Spezialprodukt');
      expect(result.storeName, isEmpty);
    });

    test('does not use an unpriced product line as merchant before ZU ZAHLEN', () {
      final result = ReceiptOcrParser.parse('''
Spezialprodukt
ZU ZAHLEN 29,99 €
''');

      expect(result.productTitle, 'Spezialprodukt');
      expect(result.productPrice, 29.99);
      expect(result.storeName, isEmpty);
    });

    test('collapses repeated whitespace in fallback merchant names', () {
      final result = ReceiptOcrParser.parse('''
Mein  lokaler   Händler
Produkt 4,99 €
''');

      expect(result.storeName, 'Mein lokaler Händler');
      expect(result.productTitle, 'Produkt');
      expect(result.productPrice, 4.99);
    });

    test('keeps the captured image path in the scan result', () {
      final result = ReceiptOcrParser.parse('REWE\nSUMME 12,99 €', imagePath: 'receipts/bon.jpg');

      expect(result.imagePath, 'receipts/bon.jpg');
      expect(result.copyWith(imagePath: 'receipts/new.jpg').imagePath, 'receipts/new.jpg');
    });
  });
}

