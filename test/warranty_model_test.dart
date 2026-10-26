import 'package:flutter_test/flutter_test.dart';
import 'package:garantieheld/warranty_model.dart';

void main() {
  Warranty createWarranty({int months = 24, int? days}) => Warranty(
    id: 'test-id',
    title: 'Testgerät',
    storeName: 'BonKeepr',
    price: 10,
    purchaseDate: DateTime(2026, 1, 31),
    warrantyMonths: months,
    warrantyDays: days,
    category: Category.sonstiges,
    imagePath: '',
  );

  test('calculates a two-week warranty as 14 days', () {
    final warranty = createWarranty(months: 0, days: 14);

    expect(warranty.expirationDate, DateTime(2026, 2, 14));
    expect(warranty.durationLabel, '2 Wochen');
  });

  test('calculates short month warranties by calendar month', () {
    final warranty = createWarranty(months: 1);

    expect(warranty.expirationDate, DateTime(2026, 2, 28));
    expect(warranty.durationLabel, '1 Monat');
  });

  test('round-trips day-based warranty duration through the database map', () {
    final warranty = createWarranty(months: 0, days: 14);
    final restored = Warranty.fromMap(warranty.toMap());

    expect(restored.warrantyDays, 14);
    expect(restored.expirationDate, warranty.expirationDate);
  });

  test('round-trips serial number and up to three receipt paths', () {
    final warranty = Warranty(
      id: 'test-media',
      title: 'Kamera',
      storeName: 'BonKeepr',
      price: 10,
      purchaseDate: DateTime(2026, 1, 31),
      warrantyMonths: 24,
      category: Category.fahrzeug,
      imagePath: 'receipt-one.jpg',
      storeAddress: 'Musterstraße 12, 10115 Berlin',
      receiptPaths: const [
        'receipt-one.jpg',
        'receipt-two.pdf',
        'receipt-three.png',
      ],
      serialNumber: 'SN-12345',
    );

    final restored = Warranty.fromMap(warranty.toMap());
    expect(restored.serialNumber, 'SN-12345');
    expect(restored.category, Category.fahrzeug);
    expect(restored.storeAddress, 'Musterstraße 12, 10115 Berlin');
    expect(restored.allReceiptPaths, warranty.allReceiptPaths);
  });

  test('legacy warranties expose imagePath as their only receipt', () {
    final warranty = createWarranty();
    final restored = Warranty.fromMap(warranty.toMap());

    expect(restored.allReceiptPaths, isEmpty);
    final legacy = Warranty.fromMap({
      ...warranty.toMap(),
      'imagePath': 'receipt.jpg',
      'receiptPaths': null,
    });
    expect(legacy.allReceiptPaths, ['receipt.jpg']);
    expect(legacy.storeAddress, isEmpty);
  });
}
