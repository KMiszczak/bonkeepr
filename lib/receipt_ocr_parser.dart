class ReceiptOcrResult {
  const ReceiptOcrResult({
    required this.fullText,
    this.totalAmount,
    this.purchaseDate,
    this.storeName = '',
    this.productTitle = '',
    this.imagePath = '',
  });

  final String fullText;
  final double? totalAmount;
  final DateTime? purchaseDate;
  final String storeName;
  final String productTitle;
  final String imagePath;

  ReceiptOcrResult copyWith({String? imagePath}) => ReceiptOcrResult(
        fullText: fullText,
        totalAmount: totalAmount,
        purchaseDate: purchaseDate,
        storeName: storeName,
        productTitle: productTitle,
        imagePath: imagePath ?? this.imagePath,
      );
}

class ReceiptOcrParser {
  static final _datePattern = RegExp(
    r'(^|[^\d])([0-3]?\d)[./-]([01]?\d)[./-](\d{2}|\d{4})(?!\d)',
  );
  static final _pricePattern = RegExp(
    r'(^|[^\d])(\d{1,3}(?:[ .]\d{3})*(?:[,.]\d{2})|\d+(?:[,.]\d{2}))(?!\d)',
  );
  static final _totalLabelPattern = RegExp(
    r'\b(?:summe|gesamt(?:betrag)?|endbetrag|zu\s+zahlen|zahlbetrag|rechnungsbetrag|total(?:\s+amount)?|betrag|bar(?:zahlung)?|ec\s*[- ]?\s*karte|girocard|kreditkarte|visa|mastercard)\b',
    caseSensitive: false,
  );
  static final _currencyPattern = RegExp(r'\bEUR\b|€', caseSensitive: false);
  static final _knownStores = <(RegExp, String)>[
    (RegExp(r'media\s*markt', caseSensitive: false), 'MediaMarkt'),
    (RegExp(r'\bsaturn\b', caseSensitive: false), 'Saturn'),
    (RegExp(r'\brewe\b', caseSensitive: false), 'REWE'),
    (RegExp(r'\bikea\b', caseSensitive: false), 'IKEA'),
  ];

  static ReceiptOcrResult parse(String text, {String imagePath = ''}) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    return ReceiptOcrResult(
      fullText: text,
      totalAmount: _findTotal(lines),
      purchaseDate: _findDate(text),
      storeName: _findStore(lines),
      productTitle: _findProductTitle(lines),
      imagePath: imagePath,
    );
  }

  static double? _findTotal(List<String> lines) {
    double? bestAmount;
    var bestScore = -1;

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      final label = _totalLabelPattern.firstMatch(line);
      final hasCurrency = _currencyPattern.hasMatch(line);
      if (label == null && !hasCurrency) continue;

      // Remove dates first so a date such as 12.10.2026 cannot look like a price.
      final withoutDates = line.replaceAll(_datePattern, ' ');
      final prices = _pricePattern.allMatches(withoutDates).toList();
      if (prices.isEmpty) continue;

      final afterLabel = label == null
          ? prices
          : prices.where((match) => match.start >= label.end).toList();
      final candidates = afterLabel.isNotEmpty ? afterLabel : prices;
      final selected = candidates.first;
      final amount = _parseAmount(selected.group(2)!);
      if (amount == null) continue;

      final score = (label == null ? 500 : 1000) - lineIndex;
      if (score > bestScore) {
        bestScore = score;
        bestAmount = amount;
      }
    }
    return bestAmount;
  }

  static double? _parseAmount(String value) {
    var normalized = value.replaceAll(' ', '');
    final comma = normalized.lastIndexOf(',');
    final dot = normalized.lastIndexOf('.');
    if (comma >= 0 && dot >= 0) {
      if (comma > dot) {
        normalized = normalized.replaceAll('.', '').replaceFirst(',', '.');
      } else {
        normalized = normalized.replaceAll(',', '');
      }
    } else if (comma >= 0) {
      normalized = normalized.replaceFirst(',', '.');
    }
    return double.tryParse(normalized);
  }

  static DateTime? _findDate(String text) {
    for (final match in _datePattern.allMatches(text)) {
      final day = int.tryParse(match.group(2)!);
      final month = int.tryParse(match.group(3)!);
      var year = int.tryParse(match.group(4)!);
      if (day == null || month == null || year == null) continue;
      if (match.group(4)!.length == 2) year += year < 70 ? 2000 : 1900;

      try {
        final date = DateTime(year, month, day);
        if (date.year == year && date.month == month && date.day == day) {
          return date;
        }
      } on ArgumentError {
        // Ignore impossible calendar dates and continue with the next match.
      }
    }
    return null;
  }

  static String _findStore(List<String> lines) {
    for (final line in lines.take(8)) {
      for (final (pattern, storeName) in _knownStores) {
        if (pattern.hasMatch(line)) return storeName;
      }
    }

    for (final line in lines.take(5)) {
      if (line.length > 50 || RegExp(r'^\d+[\s./-]*$').hasMatch(line)) continue;
      if (RegExp(
        r'^(?:kassenbon|kundenbeleg|beleg|rechnung|quittung|datum|uhrzeit)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue;
      }
      return line;
    }
    return '';
  }

  static String _findProductTitle(List<String> lines) {
    for (final line in lines.skip(1).take(5)) {
      if (_datePattern.hasMatch(line) || _totalLabelPattern.hasMatch(line)) continue;
      if (_currencyPattern.hasMatch(line) || line.length > 48) continue;
      if (RegExp(r'^\d+[\s./-]*$').hasMatch(line)) continue;
      if (_knownStores.any((store) => store.$1.hasMatch(line))) continue;
      if (RegExp(
        r'^(?:filiale|kasse|bon|kassenbon|kundenbeleg|beleg|rechnung|quittung|datum|uhrzeit|straße|str\.?|tel\.?|www\.)\b',
        caseSensitive: false,
      ).hasMatch(line)) {
        continue;
      }
      return line;
    }
    return '';
  }
}



