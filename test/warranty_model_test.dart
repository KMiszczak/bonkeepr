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
}

