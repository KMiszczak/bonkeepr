import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import 'database_helper.dart';
import 'google_drive_backup_service.dart';
import 'notification_service.dart';
import 'warranty_model.dart';
import 'theme_controller.dart';
import 'widgets/retro_icon.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.onDataImported,
    this.onThemeModeChanged,
  });

  final Future<void> Function()? onDataImported;
  final Future<void> Function(ThemeMode)? onThemeModeChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  bool _driveStatusLoading = true;
  bool? _notificationsEnabled;
  GoogleSignInAccount? _driveAccount;
  ThemeMode _themeMode = ThemeController.instance.themeMode;

  @override
  void initState() {
    super.initState();
    _loadIntegrationStatus();
  }

  Future<void> _loadIntegrationStatus() async {
    GoogleSignInAccount? account;
    bool? notificationsEnabled;
    try {
      account = await GoogleDriveBackupService.instance.restoreSession();
    } catch (_) {}
    try {
      notificationsEnabled = await NotificationService.notificationsEnabled();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _driveAccount = account;
      _notificationsEnabled = notificationsEnabled;
      _driveStatusLoading = false;
    });
  }

  String _buildWarrantyCsv(
    List<Warranty> warranties, {
    Map<String, String> imagePaths = const {},
    Map<String, String> receiptPaths = const {},
  }) {
    const headers = [
      'id',
      'title',
      'storeName',
      'price',
      'purchaseDate',
      'warrantyMonths',
      'category',
      'imagePath',
      'receiptPaths',
      'warrantyDays',
      'serialNumber',
      'notes',
      'reminderDaysBefore',
      'storeAddress',
    ];
    final rows = <List<Object?>>[
      headers,
      for (final warranty in warranties)
        [
          warranty.id,
          warranty.title,
          warranty.storeName,
          warranty.price.toString(),
          warranty.purchaseDate.toIso8601String(),
          warranty.warrantyMonths.toString(),
          warranty.category.name,
          imagePaths[warranty.id] ?? warranty.imagePath,
          receiptPaths[warranty.id] ?? warranty.allReceiptPaths.join('|'),
          warranty.warrantyDays?.toString() ?? '',
          warranty.serialNumber ?? '',
          warranty.notes ?? '',
          warranty.reminderDaysBefore.toString(),
          warranty.storeAddress,
        ],
    ];
    return '\uFEFF${const ListToCsvConverter(fieldDelimiter: ';').convert(rows)}';
  }

  Future<void> exportFullBackupZip() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final backup = await _createFullBackupFile();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          text: 'BonKeepr-Backup (${backup.warrantyCount} Garantien)',
          files: [XFile(backup.file.path)],
        ),
      );
    } catch (_) {
      _showMessage('Das ZIP-Backup konnte nicht erstellt werden.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<({File file, int warrantyCount})> _createFullBackupFile() async {
    final warranties = await DatabaseHelper.instance.getAllWarranties();
    final archive = Archive();
    final relativeImagePaths = <String, String>{
      for (final warranty in warranties) warranty.id: '',
    };
    final relativeReceiptPaths = <String, String>{};
    archive.addFile(ArchiveFile.directory('belege/'));
    var mediaIndex = 0;
    for (final warranty in warranties) {
      final relatives = <String>[];
      for (final sourcePath in warranty.allReceiptPaths.take(3)) {
        final sourceFile = File(sourcePath);
        if (sourcePath.isEmpty || !await sourceFile.exists()) continue;
        final extension = path.extension(sourcePath).toLowerCase();
        if (!const {'.jpg', '.jpeg', '.png', '.pdf'}.contains(extension)) {
          continue;
        }
        final relativePath = 'belege/receipt_${++mediaIndex}$extension';
        archive.addFile(
          ArchiveFile.bytes(relativePath, await sourceFile.readAsBytes()),
        );
        relatives.add(relativePath);
      }
      relativeImagePaths[warranty.id] = relatives.isEmpty
          ? ''
          : relatives.first;
      relativeReceiptPaths[warranty.id] = relatives.join('|');
    }
    archive.addFile(
      ArchiveFile.string(
        'garantien.csv',
        _buildWarrantyCsv(
          warranties,
          imagePaths: relativeImagePaths,
          receiptPaths: relativeReceiptPaths,
        ),
      ),
    );

    final documents = await getApplicationDocumentsDirectory();
    final backupDirectory = Directory(
      path.join(documents.path, 'BonKeepr', 'Backups'),
    );
    await backupDirectory.create(recursive: true);
    final backupFile = File(
      path.join(backupDirectory.path, 'bonkeepr_backup.zip'),
    );
    await backupFile.writeAsBytes(ZipEncoder().encode(archive), flush: true);
    return (file: backupFile, warrantyCount: warranties.length);
  }

  List<Warranty> _parseWarrantyCsv(
    List<int> bytes, {
    String Function(String imagePath)? resolveImagePath,
  }) {
    final content = utf8.decode(bytes).replaceFirst('\uFEFF', '');
    final rows = const CsvToListConverter(
      fieldDelimiter: ';',
      shouldParseNumbers: false,
    ).convert(content);
    if (rows.isEmpty) {
      throw const FormatException('Die CSV-Datei enthält keine Garantien.');
    }
    final header = rows.first.map((value) => value.toString().trim()).toList();
    const requiredColumns = [
      'id',
      'title',
      'storeName',
      'price',
      'purchaseDate',
      'warrantyMonths',
      'category',
      'imagePath',
    ];
    if (!requiredColumns.every(header.contains)) {
      throw const FormatException('Die CSV-Datei ist kein BonKeepr-Backup.');
    }
    final indexes = {for (var i = 0; i < header.length; i++) header[i]: i};
    String valueAt(List<dynamic> row, String column) {
      final index = indexes[column];
      return index == null || index >= row.length ? '' : row[index].toString();
    }

    final warranties = <Warranty>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (row.every((value) => value.toString().trim().isEmpty)) continue;
      final price = double.tryParse(
        valueAt(row, 'price').trim().replaceAll(',', '.'),
      );
      final purchaseDate = DateTime.tryParse(
        valueAt(row, 'purchaseDate').trim(),
      );
      final months = int.tryParse(valueAt(row, 'warrantyMonths').trim());
      final id = valueAt(row, 'id').trim();
      final title = valueAt(row, 'title').trim();
      if (id.isEmpty ||
          title.isEmpty ||
          price == null ||
          !price.isFinite ||
          purchaseDate == null ||
          months == null ||
          months < 0) {
        throw FormatException(
          'Ungültiger Eintrag in CSV-Zeile ${rowIndex + 1}.',
        );
      }
      final categoryName = valueAt(row, 'category').trim();
      final imagePath = valueAt(row, 'imagePath');
      final storedReceiptPaths = valueAt(row, 'receiptPaths');
      final relativePaths =
          (storedReceiptPaths.isEmpty ? imagePath : storedReceiptPaths)
              .split('|')
              .where((value) => value.isNotEmpty)
              .toList();
      final resolvedPaths = relativePaths
          .map((value) => resolveImagePath?.call(value) ?? value)
          .where((value) => value.isNotEmpty)
          .toList();
      warranties.add(
        Warranty(
          id: id,
          title: title,
          storeName: valueAt(row, 'storeName'),
          storeAddress: valueAt(row, 'storeAddress'),
          price: price,
          purchaseDate: purchaseDate,
          warrantyMonths: months,
          category: Category.values.firstWhere(
            (category) => category.name == categoryName,
            orElse: () => Category.sonstiges,
          ),
          imagePath: resolvedPaths.isNotEmpty
              ? resolvedPaths.first
              : (resolveImagePath?.call(imagePath) ?? imagePath),
          receiptPaths: resolvedPaths,
          warrantyDays: int.tryParse(valueAt(row, 'warrantyDays')),
          serialNumber: valueAt(row, 'serialNumber').isEmpty
              ? null
              : valueAt(row, 'serialNumber'),
          notes: valueAt(row, 'notes').isEmpty ? null : valueAt(row, 'notes'),
          reminderDaysBefore:
              int.tryParse(valueAt(row, 'reminderDaysBefore')) ?? 30,
        ),
      );
    }
    return warranties;
  }

  Future<void> importFullBackupZip() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
      );
      if (selection == null || selection.files.isEmpty || !mounted) return;
      final zipBytes = selection.files.single.bytes;
      if (zipBytes == null) {
        _showMessage('Die ausgewählte ZIP-Datei konnte nicht gelesen werden.');
        return;
      }
      await _restoreBackupBytes(zipBytes);
    } on FormatException {
      _showMessage(
        'Das ZIP-Backup ist ungültig oder enthält keine gültige CSV.',
      );
    } catch (_) {
      _showMessage('Das ZIP-Backup konnte nicht wiederhergestellt werden.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackupBytes(List<int> zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
    ArchiveFile? csvFile;
    for (final entry in archive) {
      final entryName = entry.name.replaceAll('\\', '/');
      if (entryName == 'garantien.csv' && entry.isFile) {
        csvFile = entry;
        break;
      }
    }
    if (csvFile == null) {
      throw const FormatException('Im ZIP-Archiv fehlt garantien.csv.');
    }

    final documents = await getApplicationDocumentsDirectory();
    final receiptsDirectory = Directory(path.join(documents.path, 'receipts'));
    await receiptsDirectory.create(recursive: true);
    final extractedMedia = <String, String>{};
    var extractedCount = 0;
    for (final entry in archive) {
      if (!entry.isFile || entry.isSymbolicLink) continue;
      final archivePath = entry.name.replaceAll('\\', '/');
      final segments = archivePath.split('/');
      if (segments.length < 2 ||
          segments.first != 'belege' ||
          segments.any(
            (segment) => segment.isEmpty || segment == '.' || segment == '..',
          )) {
        continue;
      }
      final extension = path.extension(segments.last).toLowerCase();
      if (!const {'.jpg', '.jpeg', '.png', '.pdf'}.contains(extension)) {
        continue;
      }
      final localFile = File(
        path.join(
          receiptsDirectory.path,
          'receipt_${DateTime.now().microsecondsSinceEpoch}_${++extractedCount}$extension',
        ),
      );
      await localFile.writeAsBytes(entry.content, flush: true);
      extractedMedia[archivePath] = localFile.path;
    }

    String resolveMediaPath(String imagePath) {
      final normalizedPath = imagePath.replaceAll('\\', '/');
      final segments = normalizedPath.split('/');
      if (segments.length < 2 ||
          segments.first != 'belege' ||
          segments.any(
            (segment) => segment.isEmpty || segment == '.' || segment == '..',
          )) {
        return '';
      }
      return extractedMedia[normalizedPath] ?? '';
    }

    final warranties = _parseWarrantyCsv(
      csvFile.content,
      resolveImagePath: resolveMediaPath,
    );
    await DatabaseHelper.instance.importWarranties(warranties);
    if (!mounted) return;
    await widget.onDataImported?.call();
    _showMessage(
      '${warranties.length} Garantien und $extractedCount Belege wurden wiederhergestellt.',
    );
  }

  Future<void> _createInsuranceReport() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final all = await DatabaseHelper.instance.getAllWarranties();
      final active = all.where((item) => !item.isExpired).toList()
        ..sort((a, b) => a.expirationDate.compareTo(b.expirationDate));
      final total = active.fold<double>(0, (sum, item) => sum + item.price);
      final formatter = DateFormat('dd.MM.yyyy', 'de_DE');
      final document = pw.Document();
      pw.MemoryImage? logo;
      try {
        logo = pw.MemoryImage(
          (await rootBundle.load(
            'assets/bonkeeprlogotransparent.png',
          )).buffer.asUint8List(),
        );
      } catch (_) {}
      document.addPage(
        pw.MultiPage(
          build: (_) => [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (logo != null)
                  pw.Image(logo, width: 92, height: 48, fit: pw.BoxFit.contain)
                else
                  pw.Text(
                    'BonKeepr',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                pw.Text('Erstellt am ${formatter.format(DateTime.now())}'),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Versicherungs-Report',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Gesamtwert aktiver Garantien: ${NumberFormat.currency(locale: 'de_DE', symbol: '€').format(total)}',
            ),
            pw.SizedBox(height: 18),
            pw.TableHelper.fromTextArray(
              headers: const [
                'Titel',
                'Händler',
                'Kaufdatum',
                'Ablaufdatum',
                'Preis',
                'Seriennummer',
                'Notizen',
              ],
              data: [
                for (final item in active)
                  [
                    item.title,
                    item.storeName,
                    formatter.format(item.purchaseDate),
                    formatter.format(item.expirationDate),
                    NumberFormat.currency(
                      locale: 'de_DE',
                      symbol: '€',
                    ).format(item.price),
                    item.serialNumber ?? '—',
                    item.notes ?? '—',
                  ],
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: pdf.PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: pdf.PdfColor(0.063, 0.725, 0.506),
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              cellAlignment: pw.Alignment.centerLeft,
              border: pw.TableBorder.all(
                color: pdf.PdfColor(0.796, 0.835, 0.882),
                width: 0.4,
              ),
            ),
          ],
        ),
      );
      for (final item in active) {
        for (final imagePath in item.allReceiptPaths.take(3)) {
          if (_isPdf(imagePath)) continue;
          final file = File(imagePath);
          if (!await file.exists()) continue;
          final image = pw.MemoryImage(await file.readAsBytes());
          document.addPage(
            pw.Page(
              build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Belegnachweis · ${item.title}',
                    style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Expanded(
                    child: pw.Center(
                      child: pw.Image(image, fit: pw.BoxFit.contain),
                    ),
                  ),
                  pw.Text(
                    'Kaufdatum: ${formatter.format(item.purchaseDate)} · Seriennummer: ${item.serialNumber ?? '—'}',
                  ),
                ],
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      await Printing.layoutPdf(
        name: 'bonkeepr_versicherungsreport.pdf',
        onLayout: (_) => document.save(),
      );
    } catch (_) {
      _showMessage('Der Versicherungs-Report konnte nicht erstellt werden.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isPdf(String value) => path.extension(value).toLowerCase() == '.pdf';

  Future<void> _selectTheme(ThemeMode? mode) async {
    if (mode == null) return;
    setState(() => _themeMode = mode);
    await widget.onThemeModeChanged?.call(mode);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showComingSoon(String feature) {
    _showMessage('$feature wird in einem späteren Update verfügbar sein.');
  }

  Future<void> _setDriveSync(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final account = GoogleDriveBackupService.instance;
      if (enabled) {
        _driveAccount = await account.signIn();
      } else {
        await account.signOut();
        _driveAccount = null;
      }
      if (mounted) setState(() {});
    } catch (_) {
      _showMessage(
        'Google-Anmeldung fehlgeschlagen. Bitte OAuth-Konfiguration und Drive API prüfen.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadDriveBackup() async {
    if (_busy || _driveAccount == null) return;
    setState(() => _busy = true);
    try {
      final backup = await _createFullBackupFile();
      await GoogleDriveBackupService.instance.uploadBackup(backup.file.path);
      _showMessage(
        'Backup mit ${backup.warrantyCount} Garantien in Google Drive gespeichert.',
      );
    } catch (_) {
      _showMessage(
        'Das Backup konnte nicht in Google Drive hochgeladen werden.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreDriveBackup() async {
    if (_busy || _driveAccount == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await GoogleDriveBackupService.instance
          .downloadLatestBackup();
      if (bytes == null) {
        _showMessage(
          'In Google Drive wurde noch kein BonKeepr-Backup gefunden.',
        );
        return;
      }
      await _restoreBackupBytes(bytes);
    } on FormatException {
      _showMessage('Das Google-Drive-Backup ist ungültig oder unvollständig.');
    } catch (_) {
      _showMessage(
        'Das Backup konnte nicht aus Google Drive wiederhergestellt werden.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkNotificationPermission() async {
    try {
      final enabled = await NotificationService.notificationsEnabled();
      if (mounted) setState(() => _notificationsEnabled = enabled);
    } catch (_) {}
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final enabled = await NotificationService.requestPermission();
      if (!mounted) return;
      setState(() => _notificationsEnabled = enabled);
      _showMessage(
        enabled
            ? 'Benachrichtigungen sind aktiviert.'
            : 'Benachrichtigungen sind nicht erlaubt. Bitte prüfe die Geräteeinstellungen.',
      );
    } catch (_) {
      _showMessage(
        'Benachrichtigungsberechtigungen konnten nicht geprüft werden.',
      );
    }
  }

  Future<void> _sendTestNotification() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final scheduled = await NotificationService.sendTestNotification();
      _showMessage(
        scheduled
            ? 'Test-Benachrichtigung wird in 5 Sekunden gesendet.'
            : 'Benachrichtigung nicht möglich. Bitte erlaube Benachrichtigungen in den Einstellungen.',
      );
      await _checkNotificationPermission();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRetroMode = ThemeController.instance.isRetroMode;
    final driveSubtitle = _driveStatusLoading
        ? 'Anmeldestatus wird geprüft …'
        : _driveAccount?.email ?? 'Nicht angemeldet';
    final notificationSubtitle = _notificationsEnabled == null
        ? 'Status prüfen oder Berechtigung erteilen'
        : _notificationsEnabled!
        ? 'Berechtigung erteilt'
        : 'Nicht erlaubt · antippen zum Aktivieren';
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Einstellungen',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _SettingsSection(
            title: 'DATENSICHERUNG & EXPORT',
            children: [
              _SettingsTile(
                icon: Icons.archive_outlined,
                title: 'Backup erstellen',
                subtitle: 'Garantien, Fotos und PDFs als ZIP teilen',
                onTap: _busy ? null : exportFullBackupZip,
                trailing: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              _SettingsTile(
                icon: Icons.unarchive_outlined,
                title: 'Backup wiederherstellen',
                subtitle:
                    'Garantien und Belege aus einer ZIP-Datei importieren',
                onTap: _busy ? null : importFullBackupZip,
              ),
              _SettingsTile(
                icon: Icons.policy_outlined,
                title: 'Versicherungs-Report erstellen (PDF)',
                subtitle:
                    'Aktive Garantien und Foto-Nachweise drucken oder teilen',
                onTap: _busy ? null : _createInsuranceReport,
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: 'ERSCHEINUNGSBILD',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: DropdownButtonFormField<ThemeMode>(
                  value: _themeMode,
                  decoration: InputDecoration(
                    labelText: 'Theme auswählen',
                    border: OutlineInputBorder(
                      borderRadius: isRetroMode
                          ? BorderRadius.zero
                          : BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isRetroMode ? Colors.black : Colors.grey,
                        width: isRetroMode ? 3 : 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: isRetroMode
                          ? BorderRadius.zero
                          : BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isRetroMode ? Colors.black : Colors.grey,
                        width: isRetroMode ? 3 : 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: isRetroMode
                          ? BorderRadius.zero
                          : BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isRetroMode
                            ? const Color(0xFF00E5FF)
                            : Theme.of(context).colorScheme.primary,
                        width: isRetroMode ? 3 : 2,
                      ),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dunkel (Dark)'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Hell (Light)'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('Systemstandard'),
                    ),
                  ],
                  onChanged: _selectTheme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: 'CLOUD BACKUP',
            children: [
              SwitchListTile.adaptive(
                value: _driveAccount != null,
                onChanged: _driveStatusLoading || _busy ? null : _setDriveSync,
                secondary: const _SettingsIcon(icon: Icons.cloud_outlined),
                title: const Text(
                  'Google Drive Sync',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(driveSubtitle),
                activeThumbColor: isRetroMode
                    ? const Color(0xFF00FF66)
                    : const Color(0xFF10B981),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              _SettingsTile(
                icon: Icons.cloud_upload_outlined,
                title: 'Backup jetzt hochladen',
                subtitle: _driveAccount == null
                    ? 'Zuerst Google Drive verbinden'
                    : 'Aktuelles Backup im privaten AppData-Ordner speichern',
                onTap: _busy || _driveAccount == null
                    ? null
                    : _uploadDriveBackup,
              ),
              _SettingsTile(
                icon: Icons.cloud_download_outlined,
                title: 'Backup aus Google Drive wiederherstellen',
                subtitle: _driveAccount == null
                    ? 'Zuerst Google Drive verbinden'
                    : 'Letztes hochgeladenes Backup importieren',
                onTap: _busy || _driveAccount == null
                    ? null
                    : _restoreDriveBackup,
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: 'ALLGEMEIN & APP-INFO',
            children: [
              _SettingsTile(
                icon: Icons.notifications_active_outlined,
                title: 'Benachrichtigungen',
                subtitle: notificationSubtitle,
                onTap: _requestNotificationPermission,
              ),
              _SettingsTile(
                icon: Icons.notification_add_outlined,
                title: 'Test-Benachrichtigung senden',
                subtitle: 'Lokale Benachrichtigung in 5 Sekunden auslösen',
                onTap: _busy ? null : _sendTestNotification,
              ),
              const _SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'Über BonKeepr',
                subtitle: 'Version 1.0.0',
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Datenschutz',
                subtitle: 'Informationen folgen',
                onTap: () => _showComingSoon('Die Datenschutzhinweise'),
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                title: 'Impressum',
                subtitle: 'Informationen folgen',
                onTap: () => _showComingSoon('Das Impressum'),
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isRetroMode = ThemeController.instance.isRetroMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: TextStyle(
              color: isRetroMode
                  ? const Color(0xFFFFD700)
                  : Theme.of(context).colorScheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Container(
          decoration: isRetroMode
              ? const BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black,
                      offset: Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ],
                )
              : null,
          child: Material(
            color: isRetroMode
                ? const Color(0xFF1A0933)
                : dark
                ? const Color(0xFF1E293B)
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: isRetroMode
                  ? BorderRadius.zero
                  : BorderRadius.circular(18),
              side: isRetroMode
                  ? const BorderSide(color: Colors.black, width: 3)
                  : BorderSide.none,
            ),
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isRetroMode = ThemeController.instance.isRetroMode;
    return Column(
      children: [
        ListTile(
          leading: _SettingsIcon(icon: icon),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
          trailing:
              trailing ??
              (onTap == null
                  ? null
                  : RetroIcon(
                      Icons.chevron_right_rounded,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.54),
                    )),
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 3,
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Divider(
              height: 1,
              thickness: 1,
              color: isRetroMode
                  ? Colors.black
                  : dark
                  ? const Color(0xFF334155)
                  : const Color(0xFFE2E8F0),
            ),
          ),
      ],
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isRetroMode = ThemeController.instance.isRetroMode;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isRetroMode
            ? const Color(0xFF121212)
            : dark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF1F5F9),
        borderRadius: isRetroMode
            ? BorderRadius.zero
            : BorderRadius.circular(12),
        border: isRetroMode ? Border.all(color: Colors.black, width: 2) : null,
      ),
      child: RetroIcon(
        icon,
        color: Theme.of(context).colorScheme.primary,
        size: 21,
      ),
    );
  }
}
