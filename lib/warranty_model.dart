enum Category { elektronik, haushalt, moebel, werkzeug, kleidung, sonstiges }

class Warranty {
  const Warranty({
    required this.id,
    required this.title,
    required this.storeName,
    required this.price,
    required this.purchaseDate,
    required this.warrantyMonths,
    required this.category,
    required this.imagePath,
    this.receiptPaths = const [],
    this.warrantyDays,
    this.serialNumber,
    this.notes,
    this.reminderDaysBefore = 30,
  });

  final String id;
  final String title;
  final String storeName;
  final double price;
  final DateTime purchaseDate;
  final int warrantyMonths;
  final Category category;
  final String imagePath;
  final List<String> receiptPaths;

  List<String> get allReceiptPaths => receiptPaths.isNotEmpty
      ? receiptPaths
      : imagePath.isEmpty
      ? const []
      : [imagePath];
  final int? warrantyDays;
  final String? serialNumber;
  final String? notes;
  final int reminderDaysBefore;

  /// Adds calendar months and clamps to the last valid day of the target month.
  DateTime get expirationDate {
    if (warrantyDays != null) {
      return purchaseDate.add(Duration(days: warrantyDays!));
    }
    final monthIndex =
        purchaseDate.year * 12 + purchaseDate.month - 1 + warrantyMonths;
    final year = monthIndex ~/ 12;
    final month = monthIndex % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, purchaseDate.day.clamp(1, lastDay).toInt());
  }

  int get remainingDays {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final expirationDateOnly = DateTime(
      expirationDate.year,
      expirationDate.month,
      expirationDate.day,
    );
    return expirationDateOnly.difference(todayDate).inDays;
  }

  bool get isExpired => remainingDays < 0;

  String get durationLabel {
    if (warrantyDays != null) {
      return warrantyDays == 14 ? '2 Wochen' : '$warrantyDays Tage';
    }
    return warrantyMonths == 1 ? '1 Monat' : '$warrantyMonths Monate';
  }

  /// A warranty is expiring soon if it expires today or within the next 29 days.
  bool get isExpiringSoon => remainingDays >= 0 && remainingDays < 30;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'storeName': storeName,
    'price': price,
    'purchaseDate': purchaseDate.toIso8601String(),
    'warrantyMonths': warrantyMonths,
    'category': category.name,
    'imagePath': imagePath,
    'receiptPaths': receiptPaths.isEmpty ? null : receiptPaths.join('|'),
    'warrantyDays': warrantyDays,
    'serialNumber': serialNumber,
    'notes': notes,
    'reminderDaysBefore': reminderDaysBefore,
  };

  factory Warranty.fromMap(Map<String, Object?> map) {
    final categoryName = map['category'] as String?;
    final storedPaths = map['receiptPaths'] as String?;
    return Warranty(
      id: map['id'] as String,
      title: map['title'] as String,
      storeName: map['storeName'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      purchaseDate: DateTime.parse(map['purchaseDate'] as String),
      warrantyMonths: map['warrantyMonths'] as int? ?? 24,
      category: Category.values.firstWhere(
        (value) => value.name == categoryName,
        orElse: () => Category.sonstiges,
      ),
      imagePath: map['imagePath'] as String? ?? '',
      receiptPaths: storedPaths == null || storedPaths.isEmpty
          ? const []
          : storedPaths.split('|'),
      warrantyDays: map['warrantyDays'] as int?,
      serialNumber: map['serialNumber'] as String?,
      notes: map['notes'] as String?,
      reminderDaysBefore: map['reminderDaysBefore'] as int? ?? 30,
    );
  }
}
