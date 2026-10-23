# GarantieHeld

Lokaler Beleg- und Garantie-Safe für Android. Beim Scannen wird das Bonfoto zur Analyse an die Gemini API gesendet; bei fehlender Verbindung oder nicht konfiguriertem API-Key kann die Garantie manuell erfasst werden.

## Gemini für lokale Entwicklung konfigurieren

1. Erstelle einen Gemini API-Key in Google AI Studio.
2. Starte die App aus dem Projektordner und übergib den Key als Dart-Define:

```powershell
flutter run -d <Pixel-Geräte-ID> --dart-define=GEMINI_API_KEY=<DEIN_API_KEY>
```

Das Modell verwendet standardmäßig `gemini-3.8-flash`. Für ein anderes unterstütztes Flash-Modell kann es ebenfalls beim Start gesetzt werden:

```powershell
flutter run -d <Pixel-Geräte-ID> --dart-define=GEMINI_API_KEY=<DEIN_API_KEY> --dart-define=GEMINI_MODEL=<MODELLNAME>
```

Für eine APK:

```powershell
flutter build apk --release --dart-define=GEMINI_API_KEY=<DEIN_API_KEY>
```

**Architektur:** GarantieHeld sendet die Anfrage direkt vom Gerät an die Gemini API. Ein eigenes Backend wird dafür nicht verwendet.

**Sicherheit:** Ein in eine mobile App eingebundener API-Key ist nicht geheim und kann aus einem APK extrahiert werden. Wenn du bewusst ohne Backend arbeitest, nutze einen separaten Key nur für diese App, schränke ihn in Google AI Studio/Google Cloud soweit möglich auf die benötigte API ein, setze Quoten und überwache die Nutzung. Den Key niemals committen oder in Quellcode/Logs schreiben.

**Datenschutz:** Das Bonfoto verlässt bei der KI-Analyse das Gerät und wird an Google übertragen. Die App zeigt diesen Hinweis bereits auf dem Kamera-Screen an.
