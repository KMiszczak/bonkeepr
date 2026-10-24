import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'database_helper.dart';
import 'warranty_model.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _exportWarranties() async {
    setState(() => _busy = true);
    try {
      final warranties = await DatabaseHelper.instance.getAllWarranties();
      const headers = [
        'id',
        'title',
        'storeName',
        'price',
        'purchaseDate',
        'warrantyMonths',
        'category',
        'imagePath',
        'warrantyDays',
        'serialNumber',
        'notes',
        'reminderDaysBefore',
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
            warranty.imagePath,
            warranty.warrantyDays?.toString() ?? '',
            warranty.serialNumber ?? '',
            warranty.notes ?? '',
            warranty.reminderDaysBefore.toString(),
          ],
      ];
      final csv = '\uFEFF${const ListToCsvConverter(fieldDelimiter: ';').convert(rows)}';
      final documents = await getApplicationDocumentsDirectory();
      final exportDirectory = Directory(path.join(documents.path, 'BonKeepr', 'Backups'));
      await exportDirectory.create(recursive: true);
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File(path.join(exportDirectory.path, 'bonkeepr_$timestamp.csv'));
      await file.writeAsString(csv, encoding: utf8, flush: true);
      if (!mounted) return;
      _showMessage('${warranties.length} Garantien lokal exportiert.');
      await SharePlus.instance.share(
        ShareParams(
          text: 'BonKeepr-Datensicherung (${warranties.length} Garantien)',
          files: [XFile(file.path)],
        ),
      );
    } catch (_) {
      _showMessage('Der CSV-Export ist fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importWarranties() async {
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (selection == null || selection.files.isEmpty || !mounted) return;
      final bytes = selection.files.single.bytes;
      if (bytes == null) {
        _showMessage('Die ausgewählte CSV-Datei konnte nicht gelesen werden.');
        return;
      }

      final content = utf8.decode(bytes).replaceFirst('\uFEFF', '');
      final rows = const CsvToListConverter(
        fieldDelimiter: ';',
        shouldParseNumbers: false,
      ).convert(content);
      if (rows.length < 2) {
        _showMessage('Die CSV-Datei enthält keine Garantien.');
        return;
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
        _showMessage('Die CSV-Datei ist kein BonKeepr-Backup.');
        return;
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
        final price = double.tryParse(valueAt(row, 'price').trim().replaceAll(',', '.'));
        final purchaseDate = DateTime.tryParse(valueAt(row, 'purchaseDate').trim());
        final months = int.tryParse(valueAt(row, 'warrantyMonths').trim());
        final id = valueAt(row, 'id').trim();
        final title = valueAt(row, 'title').trim();
        if (id.isEmpty || title.isEmpty || price == null || !price.isFinite ||
            purchaseDate == null || months == null || months < 0) {
          _showMessage('Ungültiger Eintrag in CSV-Zeile ${rowIndex + 1}.');
          return;
        }
        final categoryName = valueAt(row, 'category').trim();
        warranties.add(
          Warranty(
            id: id,
            title: title,
            storeName: valueAt(row, 'storeName'),
            price: price,
            purchaseDate: purchaseDate,
            warrantyMonths: months,
            category: Category.values.firstWhere(
              (category) => category.name == categoryName,
              orElse: () => Category.sonstiges,
            ),
            imagePath: valueAt(row, 'imagePath'),
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
      if (warranties.isEmpty) {
        _showMessage('Die CSV-Datei enthält keine importierbaren Garantien.');
        return;
      }

      await DatabaseHelper.instance.importWarranties(warranties);
      if (!mounted) return;
      _showMessage('${warranties.length} Garantien wurden importiert.');
    } on FormatException {
      _showMessage('Die CSV-Datei ist ungültig oder nicht UTF-8-kodiert.');
    } catch (_) {
      _showMessage('Der CSV-Import ist fehlgeschlagen.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showComingSoon(String feature) {
    _showMessage('$feature wird in einem späteren Update verfügbar sein.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
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
                icon: Icons.file_download_outlined,
                title: 'Garantien exportieren',
                subtitle: 'CSV-Backup lokal speichern und teilen',
                onTap: _busy ? null : _exportWarranties,
                trailing: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              _SettingsTile(
                icon: Icons.photo_library_outlined,
                title: 'Fotos sichern',
                subtitle: 'Bilder als ZIP-Backup exportieren',
                onTap: () => _showComingSoon('Der Foto-ZIP-Export'),
              ),
              _SettingsTile(
                icon: Icons.file_upload_outlined,
                title: 'Daten importieren',
                subtitle: 'BonKeepr-CSV-Backup wiederherstellen',
                onTap: _importWarranties,
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: 'CLOUD BACKUP',
            children: [
              SwitchListTile.adaptive(
                value: false,
                onChanged: null,
                secondary: const _SettingsIcon(icon: Icons.cloud_outlined),
                title: const Text(
                  'Google Drive Sync',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Nicht angemeldet · Vorbereitung',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                ),
                activeThumbColor: const Color(0xFF10B981),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsSection(
            title: 'ALLGEMEIN & APP-INFO',
            children: [
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Material(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
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
    return Column(
      children: [
        ListTile(
          leading: _SettingsIcon(icon: icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            subtitle,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
          ),
          trailing: trailing ??
              (onTap == null
                  ? null
                  : const Icon(Icons.chevron_right_rounded, color: Colors.white54)),
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 72),
            child: Divider(height: 1, thickness: 1, color: Color(0xFF334155)),
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
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: const Color(0xFF10B981), size: 21),
    );
  }
}


