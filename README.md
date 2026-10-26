# GarantieHeld

Lokaler Beleg- und Garantie-Safe für Android. Beim Scannen wird das Bonfoto zur Analyse an die Gemini API gesendet; bei fehlender Verbindung oder nicht konfiguriertem API-Key kann die Garantie manuell erfasst werden.

## Gemini für lokale Entwicklung konfigurieren

1. Erstelle einen Gemini API-Key in Google AI Studio.
2. Starte die App aus dem Projektordner und übergib den Key als Dart-Define:

```powershell
flutter run -d <Pixel-Geräte-ID> --dart-define=GEMINI_API_KEY=<DEIN_API_KEY>
```

Die KI-Analyse versucht der Reihe nach `gemini-3.8-flash`, `gemini-3.7-flash`, `gemini-3.5-flash` und `gemini-3.5-flash-lite`. Jeder Versuch hat ein Timeout von 10 Sekunden; bei einem Fehler wird sofort das nächste Modell verwendet.

Für eine APK:

```powershell
flutter build apk --release --dart-define=GEMINI_API_KEY=<DEIN_API_KEY>
```

**Architektur:** GarantieHeld sendet die Anfrage direkt vom Gerät an die Gemini API. Ein eigenes Backend wird dafür nicht verwendet.

**Sicherheit:** Ein in eine mobile App eingebundener API-Key ist nicht geheim und kann aus einem APK extrahiert werden. Wenn du bewusst ohne Backend arbeitest, nutze einen separaten Key nur für diese App, schränke ihn in Google AI Studio/Google Cloud soweit möglich auf die benötigte API ein, setze Quoten und überwache die Nutzung. Den Key niemals committen oder in Quellcode/Logs schreiben.

**Datenschutz:** Das Bonfoto verlässt bei der KI-Analyse das Gerät und wird an Google übertragen. Die App zeigt diesen Hinweis bereits auf dem Kamera-Screen an.

## Google Drive Backup konfigurieren

1. Aktiviere in deinem Google-Cloud-Projekt die **Google Drive API** und richte den OAuth-Zustimmungsbildschirm ein.
2. Lege einen Android-OAuth-Client für `com.example.garantieheld` mit den SHA-1-Fingerabdrücken der verwendeten Signaturschlüssel an.
3. Lege zusätzlich einen OAuth-Client vom Typ **Webanwendung** an. Ohne `google-services.json` muss dessen Client-ID beim Start als `GOOGLE_SERVER_CLIENT_ID` übergeben werden:

```powershell
flutter run -d <Pixel-Geräte-ID> --dart-define=GEMINI_API_KEY=<DEIN_API_KEY> --dart-define=GOOGLE_SERVER_CLIENT_ID=<WEB_OAUTH_CLIENT_ID>
```

Die App fragt ausschließlich den Drive-Scope `drive.appdata` an. Backups werden als `bonkeepr_backup.zip` im privaten `appDataFolder` gespeichert; der Ordner ist nicht direkt in Google Drive sichtbar. Für Release-Builds müssen OAuth-Client und SHA-1 zum tatsächlichen Release-Signaturschlüssel passen.
