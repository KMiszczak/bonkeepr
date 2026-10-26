import 'dart:convert';
import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

import 'receipt_ocr_parser.dart';

const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
const String geminiModelName = 'gemini-3.8-flash';
const String geminiFallbackModelName = 'gemini-3.7-flash';
const List<String> geminiModelCascade = [
  geminiModelName,
  geminiFallbackModelName,
  'gemini-3.5-flash',
  'gemini-3.5-flash-lite',
];

class GeminiModelCascadeException implements Exception {
  const GeminiModelCascadeException(this.lastError);

  final Object lastError;

  @override
  String toString() => 'Alle Gemini-Modelle fehlgeschlagen: $lastError';
}

class GeminiReceiptAnalyzer {
  static bool get hasApiKey => geminiApiKey.trim().isNotEmpty;

  static const _systemPrompt = '''
Du bist ein hochpräziser Assistent für eine Garantie-App. Analysiere das Foto des Kassenbons.
1. Suche nach dem relevantesten Garantie-/Elektronik- oder langlebigen Produkt auf dem Bon (ignoriere Lebensmittel wie Wurst, Käse, Brot, Getränke etc.).
2. Extrahiere den genauen Einzelpreis dieses Produkts, bevorzugt direkt aus seiner Produktzeile. Verwende keinen Gesamtbetrag, wenn ein Einzelpreis verfügbar ist.
3. Extrahiere den Händlernamen (z.B. ALDI, REWE, MediaMarkt).
4. Extrahiere das Kaufdatum (Format: YYYY-MM-DD).
5. Wähle eine passende Kategorie: Elektronik, Haushalt, Möbel, Werkzeug, Kleidung oder Sonstiges.
Gib das Ergebnis ausschließlich als JSON-Objekt ohne Markdown zurück, mit genau diesen Feldern:
{"productName":"...","storeName":"...","price":0.00,"purchaseDate":"YYYY-MM-DD","category":"Elektronik"}
Wenn ein Wert nicht sicher erkannt wird, verwende für Text und Datum eine leere Zeichenfolge und für den Preis 0.00. Erfinde keine Werte.
''';

  static Future<ReceiptOcrResult> analyzeReceipt({
    required String imagePath,
    void Function(String status)? onStatusUpdate,
    void Function(int step)? onStepUpdate,
  }) => analyzeReceiptWithFallback(
    imagePath: imagePath,
    onStatusUpdate: onStatusUpdate,
    onStepUpdate: onStepUpdate,
  );

  static Future<ReceiptOcrResult> analyzeReceiptWithFallback({
    required String imagePath,
    void Function(String status)? onStatusUpdate,
    void Function(int step)? onStepUpdate,
  }) async {
    if (!hasApiKey) {
      throw StateError(
        'Gemini API-Key fehlt. Übergib ihn über --dart-define=GEMINI_API_KEY=…',
      );
    }

    final imageFile = File(imagePath);
    final imageBytes = await imageFile.readAsBytes();
    if (imageBytes.isEmpty)
      throw const FormatException('Das Bonfoto ist leer.');

    final mimeType = imagePath.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    final parts = [DataPart(mimeType, imageBytes)];
    for (var index = 0; index < geminiModelCascade.length; index++) {
      final step = index + 1;
      final modelName = geminiModelCascade[index];
      try {
        onStepUpdate?.call(step);
        onStatusUpdate?.call(_statusForStage(step));
        print(
          '[Gemini] [Stufe $step/4] Starte Analyse mit Modell: $modelName...',
        );
        final response = await _sendRequestWithModel(modelName, parts);
        final responseText = response.text?.trim();
        if (responseText == null || responseText.isEmpty) {
          throw const FormatException(
            'Gemini hat kein Ergebnis zurückgegeben.',
          );
        }
        final result = parseResponse(responseText, imagePath: imagePath);
        if (result.productTitle.trim().isEmpty &&
            result.storeName.trim().isEmpty &&
            result.productPrice == null &&
            result.purchaseDate == null) {
          throw const FormatException('Gemini hat keine Bon-Daten erkannt.');
        }
        onStatusUpdate?.call('Beleg erfolgreich analysiert! ✓');
        print(
          '[Gemini] [Stufe $step/4] Erfolgreich analysiert mit Modell: $modelName!',
        );
        return result;
      } catch (error) {
        print(
          '[Gemini] [Stufe $step/4] Modell $modelName fehlgeschlagen '
          '(Grund: $error). Wechsel zum nächsten Modell...',
        );
        if (step == geminiModelCascade.length) {
          print('[Gemini] Alle 4 Modelle sind fehlgeschlagen.');
          throw GeminiModelCascadeException(error);
        }
      }
    }
    throw StateError('Gemini-Modellkaskade endete ohne Ergebnis.');
  }

  static String _statusForStage(int step) => switch (step) {
    1 => 'KI analysiert Beleg (Gemini 3.8)...',
    2 => 'Server ausgelastet. Wechsle zu Gemini 3.7...',
    3 => 'Optimiere Anfrage. Wechsle zu Gemini 3.5...',
    4 => 'Finaler Versuch mit Gemini 3.5 Lite...',
    _ => 'KI analysiert Beleg...',
  };

  static Future<GenerateContentResponse> _sendRequestWithModel(
    String modelName,
    List<DataPart> parts,
  ) async {
    final httpClient = http.Client();
    try {
      final model = GenerativeModel(
        model: modelName,
        apiKey: geminiApiKey,
        httpClient: httpClient,
        systemInstruction: Content.system(_systemPrompt),
        generationConfig: GenerationConfig(
          temperature: 0.1,
          responseMimeType: 'application/json',
        ),
      );
      return await model
          .generateContent([
            Content.multi([
              TextPart(
                'Analysiere den angehängten Kassenbon und gib nur das JSON zurück.',
              ),
              ...parts,
            ]),
          ])
          .timeout(const Duration(seconds: 10));
    } finally {
      httpClient.close();
    }
  }

  static bool isServiceUnavailable(Object error) {
    final message = error.toString();
    return message.contains('Server Error [503]') ||
        message.contains('"code": 503') ||
        message.contains('"status": "UNAVAILABLE"');
  }

  static String diagnosticFor(Object error) {
    if (isServiceUnavailable(error)) {
      return 'SERVICE_UNAVAILABLE_503: ${error.toString()}';
    }
    final details = switch (error) {
      GeminiModelCascadeException(:final lastError) =>
        'MODEL_CASCADE_FAILED: ${diagnosticFor(lastError)}',
      InvalidApiKey() => 'INVALID_API_KEY: ${error.message}',
      UnsupportedUserLocation() => 'UNSUPPORTED_LOCATION: ${error.message}',
      ServerException() => 'GEMINI_SERVER_ERROR: ${error.message}',
      GenerativeAIException() => 'GEMINI_API_ERROR: ${error.message}',
      SocketException() => 'NETWORK_ERROR: $error',
      HttpException() => 'HTTP_ERROR: $error',
      FormatException() => 'RESPONSE_FORMAT_ERROR: ${error.message}',
      StateError() => 'CONFIGURATION_ERROR: ${error.message}',
      _ => '${error.runtimeType}: $error',
    };
    return geminiApiKey.isEmpty
        ? details
        : details.replaceAll(geminiApiKey, '[REDACTED]');
  }

  static ReceiptOcrResult parseResponse(
    String response, {
    String imagePath = '',
  }) {
    final jsonStart = response.indexOf('{');
    final jsonEnd = response.lastIndexOf('}');
    if (jsonStart < 0 || jsonEnd < jsonStart) {
      throw const FormatException(
        'Die Gemini-Antwort enthält kein JSON-Objekt.',
      );
    }

    final decoded = jsonDecode(response.substring(jsonStart, jsonEnd + 1));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Die Gemini-Antwort hat ein ungültiges Format.',
      );
    }

    final productName = _stringValue(decoded['productName']);
    final storeName = _stringValue(decoded['storeName']);
    final category = _stringValue(decoded['category']);
    final price = _priceValue(decoded['price']);
    final purchaseDate = DateTime.tryParse(
      _stringValue(decoded['purchaseDate']),
    );

    return ReceiptOcrResult(
      fullText: response,
      productTitle: productName,
      storeName: storeName.replaceAll(RegExp(r'\s+'), ' ').trim(),
      productPrice: price != null && price > 0 ? price : null,
      purchaseDate: purchaseDate,
      category: category,
      imagePath: imagePath,
    );
  }

  static String _stringValue(Object? value) =>
      value is String ? value.trim() : '';

  static double? _priceValue(Object? value) {
    if (value is num) return value.toDouble();
    if (value is! String) return null;

    var normalized = value.replaceAll(RegExp(r'[^\d,.]'), '');
    final comma = normalized.lastIndexOf(',');
    final dot = normalized.lastIndexOf('.');
    if (comma >= 0 && dot >= 0) {
      normalized = comma > dot
          ? normalized.replaceAll('.', '').replaceFirst(',', '.')
          : normalized.replaceAll(',', '');
    } else if (comma >= 0) {
      normalized = normalized.replaceFirst(',', '.');
    }
    return double.tryParse(normalized);
  }
}
