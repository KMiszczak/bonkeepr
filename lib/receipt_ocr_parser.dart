class ReceiptOcrResult {
  const ReceiptOcrResult({
    required this.fullText,
    this.totalAmount,
    this.productPrice,
    this.purchaseDate,
    this.storeName = '',
    this.productTitle = '',
    this.category = '',
    this.imagePath = '',
  });

  final String fullText;
  final double? totalAmount;
  final double? productPrice;
  final DateTime? purchaseDate;
  final String storeName;
  final String productTitle;
  final String category;
  final String imagePath;

  ReceiptOcrResult copyWith({String? imagePath}) => ReceiptOcrResult(
        fullText: fullText,
        totalAmount: totalAmount,
        productPrice: productPrice,
        purchaseDate: purchaseDate,
        storeName: storeName,
        productTitle: productTitle,
        category: category,
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
    r'\b(?:summe|gesamt(?:betrag)?|endbetrag|zu\s+zahlen|zahlbetrag|rechnungsbetrag|total(?:\s+amount)?|betrag|bar(?:zahlung)?|ec\s*[- ]?\s*karte|gegeben|rückgeld|girocard|kreditkarte|visa|mastercard)\b',
    caseSensitive: false,
  );
  static final _aggregateLinePattern = RegExp(
    r'\b(?:summe|zwischen(?:summe)?|gesamt|endbetrag|zahlbetrag|rechnungsbetrag|betrag|zu\s+zahlen|total|bar|ec\s*[- ]?\s*karte|gegeben|rückgeld)\b',
    caseSensitive: false,
  );
  static final _paymentLinePattern = RegExp(
    r'\b(?:bar|ec\s*[- ]?\s*karte|gegeben|rückgeld)\b',
    caseSensitive: false,
  );
  static final _dueLinePattern = RegExp(r'\bzu\s+zahlen\b', caseSensitive: false);
  static final _currencyPattern = RegExp(r'\bEUR\b|€', caseSensitive: false);
  static final _addressLinePattern = RegExp(
    r'(?:straße|strasse|str\.?|weg|platz)|(?:^|\D)\d{5}(?:\D|$)',
    caseSensitive: false,
  );
  static final _knownStores = <(RegExp, String)>[
    (RegExp(r'\ba\s*l\s*d\s*i\b', caseSensitive: false), 'ALDI'),
    (RegExp(r'\blidl\b', caseSensitive: false), 'LIDL'),
    (RegExp(r'\bedeka\b', caseSensitive: false), 'EDEKA'),
    (RegExp(r'media\s*markt', caseSensitive: false), 'MediaMarkt'),
    (RegExp(r'\bsaturn\b', caseSensitive: false), 'Saturn'),
    (RegExp(r'\brewe\b', caseSensitive: false), 'REWE'),
    (RegExp(r'\bikea\b', caseSensitive: false), 'IKEA'),
    (RegExp(r'\bbauhaus\b', caseSensitive: false), 'BAUHAUS'),
    (RegExp(r'\bh\s*&\s*m\b', caseSensitive: false), 'H&M'),
    (RegExp(r'\bkaufland\b', caseSensitive: false), 'KAUFLAND'),
    (RegExp(r'\baction\b', caseSensitive: false), 'ACTION'),
  ];

  static ReceiptOcrResult parse(String text, {String imagePath = ''}) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final knownStore = _findKnownStore(lines);
    late final (String, double?, int?) product;
    late final (String, int?) store;
    if (knownStore != null) {
      store = knownStore;
      product = _findProduct(lines, storeLineIndex: knownStore.$2);
    } else {
      final pricedProduct = _findProduct(lines, allowUnpricedFallback: false);
      store = _findStoreFallback(
        lines,
        productLineIndex: pricedProduct.$3,
      );
      product = pricedProduct.$3 != null
          ? pricedProduct
          : _findProduct(lines, storeLineIndex: store.$2);
    }

    return ReceiptOcrResult(
      fullText: text,
      totalAmount: _findTotal(lines),
      purchaseDate: _findDate(text),
      storeName: store.$1,
      productTitle: product.$1,
      productPrice: product.$2,
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

  static (String, int)? _findKnownStore(List<String> lines) {
    final candidateCount = lines.length < 5 ? lines.length : 5;
    for (var index = 0; index < candidateCount; index++) {
      final line = lines[index];
      if (_isInvalidStoreLine(line)) continue;
      for (final (pattern, storeName) in _knownStores) {
        if (pattern.hasMatch(line)) return (storeName, index);
      }
    }
    return null;
  }

  static (String, int?) _findStoreFallback(
    List<String> lines, {
    int? productLineIndex,
  }) {
    final candidateCount = lines.length < 5 ? lines.length : 5;
    for (var index = 0; index < candidateCount; index++) {
      if (index == productLineIndex) continue;
      final line = lines[index];
      if (_isInvalidStoreLine(line)) continue;
      if (index + 1 < lines.length &&
          _aggregateLinePattern.hasMatch(lines[index + 1])) {
        continue;
      }
      return (line.replaceAll(RegExp(r'\s+'), ' ').trim(), index);
    }
    return ('', null);
  }

  static bool _isInvalidStoreLine(String line) =>
      line.length > 50 ||
      _addressLinePattern.hasMatch(line) ||
      _datePattern.hasMatch(line) ||
      _pricePattern.hasMatch(line) ||
      _currencyPattern.hasMatch(line) ||
      _aggregateLinePattern.hasMatch(line) ||
      RegExp(r'^\d+[\s./-]*$').hasMatch(line) ||
      RegExp(
        r'^(?:kassenbon|kundenbeleg|beleg|rechnung|quittung|datum|uhrzeit)\b',
        caseSensitive: false,
      ).hasMatch(line);

  static (String, double?, int?) _findProduct(
    List<String> lines, {
    int? storeLineIndex,
    bool allowUnpricedFallback = true,
  }) {
    final searchEnd = lines.length < 6 ? lines.length : 6;
    final searchStart = storeLineIndex == null ? 0 : storeLineIndex + 1;
    for (var lineIndex = searchStart; lineIndex < searchEnd; lineIndex++) {
      if (lineIndex == storeLineIndex) continue;
      final line = lines[lineIndex];
      final title = _productTitleFromLine(line);
      if (title == null) continue;

      final sameLinePrice = _findProductPriceInLine(line);
      if (sameLinePrice != null) {
        return (title, sameLinePrice, lineIndex);
      }
    }

    for (var lineIndex = searchStart; lineIndex < searchEnd; lineIndex++) {
      if (lineIndex == storeLineIndex || lineIndex + 1 >= lines.length) continue;
      final title = _productTitleFromLine(lines[lineIndex]);
      if (title == null ||
          lineIndex + 1 == storeLineIndex ||
          _aggregateLinePattern.hasMatch(lines[lineIndex + 1])) {
        continue;
      }
      final nextLinePrice = _findProductPriceInLine(lines[lineIndex + 1]);
      if (nextLinePrice != null) return (title, nextLinePrice, lineIndex);
    }

    if (!allowUnpricedFallback) {
      return ('', _findFallbackPrice(lines), null);
    }

    final fallbackStart = storeLineIndex == null ? 0 : storeLineIndex + 1;
    for (var lineIndex = fallbackStart;
        lineIndex < searchEnd;
        lineIndex++) {
      final title = _productTitleFromLine(lines[lineIndex]);
      if (title == null) continue;
      return (title, _findFallbackPrice(lines), lineIndex);
    }
    return ('', _findFallbackPrice(lines), null);
  }

  static String? _productTitleFromLine(String line) {
    if (_aggregateLinePattern.hasMatch(line) ||
        _datePattern.hasMatch(line) ||
        _addressLinePattern.hasMatch(line) ||
        line.length > 60 ||
        _knownStores.any((store) => store.$1.hasMatch(line)) ||
        RegExp(
          r'^(?:filiale|kasse|bon|kassenbon|kundenbeleg|beleg|rechnung|quittung|datum|uhrzeit|straße|str\.?|tel\.?|www\.)\b',
          caseSensitive: false,
        ).hasMatch(line)) {
      return null;
    }

    final priceMatch = _datePattern.hasMatch(line)
        ? null
        : _pricePattern.firstMatch(line);
    final priceStart = priceMatch == null
        ? null
        : priceMatch.start + priceMatch.group(0)!.indexOf(priceMatch.group(2)!);
    final suffix = priceMatch == null
        ? ''
        : line.substring(priceStart! + priceMatch.group(2)!.length);
    final cleanedSuffix = RegExp(
      r'^\s*(?:€|EUR)\s+\d+\s*$',
      caseSensitive: false,
    ).hasMatch(suffix)
        ? ''
        : suffix.replaceAll(RegExp(r'€|\bEUR\b', caseSensitive: false), ' ');
    final title = priceMatch == null
        ? line
        : '${line.substring(0, priceStart!)}$cleanedSuffix'
              .replaceFirst(RegExp(r'[\s:=-]+$'), '')
              .trim();
    if (title.isEmpty ||
        _currencyPattern.hasMatch(title) ||
        RegExp(r'^\d+[\s./-]*$').hasMatch(title) ||
        RegExp(r'^\d+\s*[x×]$', caseSensitive: false).hasMatch(title)) {
      return null;
    }
    return title;
  }

  static double? _findProductPriceInLine(String line) {
    if (_aggregateLinePattern.hasMatch(line)) return null;
    final withoutDates = line.replaceAll(_datePattern, ' ');
    final match = _pricePattern.firstMatch(withoutDates);
    return match == null ? null : _parseAmount(match.group(2)!);
  }

  static double? _findFallbackPrice(List<String> lines) {
    for (final line in lines) {
      if (!_dueLinePattern.hasMatch(line) || _paymentLinePattern.hasMatch(line)) {
        continue;
      }
      final amount = _amountAfterLabel(line, _dueLinePattern.firstMatch(line)!.end);
      if (amount != null) return amount;
    }

    for (final line in lines) {
      if (!_currencyPattern.hasMatch(line) || _paymentLinePattern.hasMatch(line)) {
        continue;
      }
      if (_aggregateLinePattern.hasMatch(line)) continue;
      final withoutDates = line.replaceAll(_datePattern, ' ');
      final matches = _pricePattern.allMatches(withoutDates).toList();
      if (matches.isNotEmpty) return _parseAmount(matches.last.group(2)!);
    }
    return null;
  }

  static double? _amountAfterLabel(String line, int labelEnd) {
    final withoutDates = line.replaceAll(_datePattern, ' ');
    final matches = _pricePattern.allMatches(withoutDates).toList();
    final afterLabel = matches.where((match) => match.start >= labelEnd).toList();
    final candidates = afterLabel.isNotEmpty ? afterLabel : matches;
    return candidates.isEmpty ? null : _parseAmount(candidates.last.group(2)!);
  }
}



