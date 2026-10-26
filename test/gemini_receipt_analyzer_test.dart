import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:garantieheld/gemini_receipt_analyzer.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

void main() {
  group('GeminiReceiptAnalyzer', () {
    test('uses a currently supported default Flash model', () {
      expect(geminiModelName, 'gemini-3.8-flash');
      expect(geminiFallbackModelName, 'gemini-3.7-flash');
      expect(geminiModelCascade, [
        'gemini-3.8-flash',
        'gemini-3.7-flash',
        'gemini-3.5-flash',
        'gemini-3.5-flash-lite',
      ]);
    });

    test('parses model JSON into wizard fields', () {
      final result = GeminiReceiptAnalyzer.parseResponse(
        '''{"productName":"MOBILE ENERGIESTATION","storeName":"ALDI  SÜD","price":29.99,"purchaseDate":"2026-10-22","category":"Elektronik"}''',
        imagePath: 'receipts/bon.jpg',
      );

      expect(result.productTitle, 'MOBILE ENERGIESTATION');
      expect(result.storeName, 'ALDI SÜD');
      expect(result.productPrice, 29.99);
      expect(result.purchaseDate, DateTime(2026, 10, 22));
      expect(result.category, 'Elektronik');
      expect(result.imagePath, 'receipts/bon.jpg');
    });

    test('normalizes comma decimal price and leaves zero price unset', () {
      final result = GeminiReceiptAnalyzer.parseResponse(
        '{"productName":"Artikel","storeName":"REWE","price":"29,99","purchaseDate":"","category":"Haushalt"}',
      );
      final noPrice = GeminiReceiptAnalyzer.parseResponse(
        '{"productName":"Artikel","storeName":"REWE","price":0,"purchaseDate":"","category":"Sonstiges"}',
      );

      expect(result.productPrice, 29.99);
      expect(result.purchaseDate, isNull);
      expect(noPrice.productPrice, isNull);
    });

    test('rejects a response without a JSON object', () {
      expect(
        () => GeminiReceiptAnalyzer.parseResponse('not json'),
        throwsFormatException,
      );
    });

    test(
      'formats Gemini API errors for diagnostics without exposing a key',
      () {
        expect(
          GeminiReceiptAnalyzer.diagnosticFor(
            InvalidApiKey('API key not valid. Please pass a valid API key.'),
          ),
          contains('INVALID_API_KEY'),
        );
        expect(
          GeminiReceiptAnalyzer.diagnosticFor(
            ServerException('RESOURCE_EXHAUSTED: quota exceeded'),
          ),
          contains('RESOURCE_EXHAUSTED'),
        );
        expect(
          GeminiReceiptAnalyzer.diagnosticFor(
            TimeoutException('Gemini timed out after 10 seconds'),
          ),
          contains('TimeoutException'),
        );
      },
    );

    test('recognizes Gemini HTTP 503 as temporary service unavailability', () {
      final error = GenerativeAIException(
        'Server Error [503]: {"error":{"code":503,"status":"UNAVAILABLE"}}',
      );

      expect(GeminiReceiptAnalyzer.isServiceUnavailable(error), isTrue);
      expect(
        GeminiReceiptAnalyzer.diagnosticFor(error),
        contains('SERVICE_UNAVAILABLE_503'),
      );
    });

    test('preserves diagnostics after the model cascade is exhausted', () {
      final failure = GeminiModelCascadeException(
        GenerativeAIException('Server Error [503]: unavailable'),
      );

      expect(
        GeminiReceiptAnalyzer.diagnosticFor(failure),
        contains('SERVICE_UNAVAILABLE_503'),
      );
    });
  });
}
