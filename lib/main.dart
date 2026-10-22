import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'database_helper.dart';
import 'warranty_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  runApp(const GarantieHeldApp());
}

class GarantieHeldApp extends StatelessWidget {
  const GarantieHeldApp({super.key});

  static const emerald = Color(0xFF10B981);
  static const background = Color(0xFF0F172A);
  static const surface = Color(0xFF1E293B);

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: emerald,
        secondary: Color(0xFF34D399),
        surface: surface,
        error: Color(0xFFF87171),
      ),
      fontFamily: 'Roboto',
    );
    return MaterialApp(
      title: 'GarantieHeld',
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<Warranty>> _warrantiesFuture;
  final _currency = NumberFormat.currency(locale: 'de_DE', symbol: '€');
  final _date = DateFormat('dd.MM.yyyy', 'de_DE');

  @override
  void initState() {
    super.initState();
    _warrantiesFuture = DatabaseHelper.instance.getAllWarranties();
  }

  Future<void> _refresh() async {
    setState(() {
      _warrantiesFuture = DatabaseHelper.instance.getAllWarranties();
    });
    await _warrantiesFuture;
  }

  Future<void> _addWarranty() async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ReceiptScannerScreen()),
    );
    if (!mounted || text == null) return;
    final firstLine = text
        ?.split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    final warranty = await showDialog<Warranty>(
      context: context,
      builder: (_) => WarrantyFormDialog(initialTitle: firstLine ?? ''),
    );
    if (warranty == null || !mounted) return;
    await DatabaseHelper.instance.insertWarranty(warranty);
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Garantie lokal gespeichert.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: GarantieHeldApp.emerald),
            SizedBox(width: 10),
            Text('GarantieHeld', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<List<Warranty>>(
        future: _warrantiesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: GarantieHeldApp.emerald),
            );
          }
          if (snapshot.hasError) return _LoadError(onRetry: _refresh);

          final warranties = snapshot.data ?? const <Warranty>[];
          final active = warranties.where((item) => !item.isExpired).toList();
          final expiring = active.where((item) => item.isExpiringSoon).length;
          final protectedTotal = active.fold<double>(
            0,
            (total, item) => total + item.price,
          );
          return RefreshIndicator(
            color: GarantieHeldApp.emerald,
            onRefresh: _refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  sliver: SliverList.list(
                    children: [
                      _ProtectedValueCard(
                        amount: _currency.format(protectedTotal),
                        activeCount: active.length,
                        expiringCount: expiring,
                      ),
                      const SizedBox(height: 30),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Deine Garantien',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${warranties.length} gesamt',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.58),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (warranties.isEmpty)
                        const _EmptyState()
                      else
                        ...warranties.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _WarrantyCard(
                              warranty: item,
                              price: _currency.format(item.price),
                              purchaseDate: _date.format(item.purchaseDate),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addWarranty,
        backgroundColor: GarantieHeldApp.emerald,
        foregroundColor: const Color(0xFF052E23),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text(
          'Bon scannen',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ProtectedValueCard extends StatelessWidget {
  const _ProtectedValueCard({
    required this.amount,
    required this.activeCount,
    required this.expiringCount,
  });

  final String amount;
  final int activeCount;
  final int expiringCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF059669), Color(0xFF047857)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF059669).withOpacity(0.24),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                'GESAMTWERT GESCHÜTZT',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.86),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            amount,
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 9,
            runSpacing: 8,
            children: [
              _CountBadge(icon: Icons.shield_rounded, label: '$activeCount aktiv'),
              _CountBadge(
                icon: Icons.schedule_rounded,
                label: '$expiringCount laufen bald ab',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.16),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _WarrantyCard extends StatelessWidget {
  const _WarrantyCard({
    required this.warranty,
    required this.price,
    required this.purchaseDate,
  });

  final Warranty warranty;
  final String price;
  final String purchaseDate;

  static const _icons = <Category, IconData>{
    Category.elektronik: Icons.devices_rounded,
    Category.haushalt: Icons.kitchen_rounded,
    Category.moebel: Icons.chair_alt_rounded,
    Category.werkzeug: Icons.handyman_rounded,
    Category.kleidung: Icons.checkroom_rounded,
    Category.sonstiges: Icons.inventory_2_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final expired = warranty.isExpired;
    final statusColor = expired ? const Color(0xFFF87171) : const Color(0xFF34D399);
    final status = expired
        ? 'Abgelaufen'
        : warranty.remainingDays == 0
            ? 'Noch heute'
            : 'Noch ${warranty.remainingDays} Tage';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GarantieHeldApp.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: GarantieHeldApp.emerald.withOpacity(0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              _icons[warranty.category] ?? Icons.inventory_2_rounded,
              color: GarantieHeldApp.emerald,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  warranty.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  '${warranty.storeName.isEmpty ? 'Händler unbekannt' : warranty.storeName} · $purchaseDate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.56),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Text(price, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 34),
      decoration: BoxDecoration(
        color: GarantieHeldApp.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 42,
            color: Colors.white.withOpacity(0.55),
          ),
          const SizedBox(height: 14),
          const Text(
            'Noch keine Garantien',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Scanne deinen ersten Kassenbon und behalte deine Käufe im Blick.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.58)),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storage_rounded, size: 42, color: Color(0xFFF87171)),
            const SizedBox(height: 12),
            const Text('Die Garantien konnten nicht geladen werden.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Erneut versuchen')),
          ],
        ),
      ),
    );
  }
}

class WarrantyFormDialog extends StatefulWidget {
  const WarrantyFormDialog({super.key, this.initialTitle = ''});

  final String initialTitle;

  @override
  State<WarrantyFormDialog> createState() => _WarrantyFormDialogState();
}

class _WarrantyFormDialogState extends State<WarrantyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  final _storeController = TextEditingController();
  final _priceController = TextEditingController();
  int _warrantyMonths = 24;
  Category _category = Category.elektronik;
  DateTime _purchaseDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _storeController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final warranty = Warranty(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      storeName: _storeController.text.trim(),
      price: double.parse(_priceController.text.trim().replaceAll(',', '.')),
      purchaseDate: _purchaseDate,
      warrantyMonths: _warrantyMonths,
      category: _category,
      imagePath: '',
    );
    Navigator.of(context).pop(warranty);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: GarantieHeldApp.surface,
      title: const Text('Garantie hinzufügen'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                autofocus: widget.initialTitle.isEmpty,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Produktname *'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Bitte Produktname eingeben'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _storeController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Händler'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Kaufpreis (€) *'),
                validator: (value) {
                  final parsed = double.tryParse(
                    (value ?? '').trim().replaceAll(',', '.'),
                  );
                  return parsed == null || !parsed.isFinite || parsed < 0
                      ? 'Bitte einen gültigen Preis eingeben'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                tileColor: GarantieHeldApp.background,
                leading: const Icon(Icons.calendar_month_rounded),
                title: const Text('Kaufdatum'),
                subtitle: Text(DateFormat('dd.MM.yyyy').format(_purchaseDate)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: _purchaseDate,
                    firstDate: DateTime(1990),
                    lastDate: DateTime.now(),
                  );
                  if (selected != null) {
                    setState(() => _purchaseDate = selected);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Category>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Kategorie'),
                items: Category.values
                    .map((category) => DropdownMenuItem(
                          value: category,
                          child: Text(_categoryLabel(category)),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _category = value ?? _category),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _warrantyMonths,
                decoration: const InputDecoration(labelText: 'Garantiedauer'),
                items: const [12, 24, 36, 48, 60]
                    .map((months) => DropdownMenuItem(
                          value: months,
                          child: Text('$months Monate'),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _warrantyMonths = value ?? 24),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Speichern'),
        ),
      ],
    );
  }

  String _categoryLabel(Category category) => switch (category) {
        Category.elektronik => 'Elektronik',
        Category.haushalt => 'Haushalt',
        Category.moebel => 'Möbel',
        Category.werkzeug => 'Werkzeug',
        Category.kleidung => 'Kleidung',
        Category.sonstiges => 'Sonstiges',
      };
}

class ReceiptScannerScreen extends StatefulWidget {
  const ReceiptScannerScreen({super.key});

  @override
  State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State<ReceiptScannerScreen> {
  CameraController? _controller;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'Keine Kamera gefunden.');
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (error) {
      if (mounted) setState(() => _error = error.description ?? error.code);
    } catch (_) {
      if (mounted) setState(() => _error = 'Die Kamera konnte nicht gestartet werden.');
    }
  }

  Future<void> _captureAndRecognize() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final image = await controller.takePicture();
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final result = await recognizer.processImage(
          InputImage.fromFilePath(image.path),
        );
        if (mounted) Navigator.of(context).pop(result.text);
      } finally {
        await recognizer.close();
      }
    } on CameraException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.description ?? 'Foto konnte nicht aufgenommen werden.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Der Bon konnte nicht erkannt werden.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Kassenbon scannen'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined, size: 48),
                    const SizedBox(height: 14),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    const Text('Du kannst die Garantie anschließend manuell erfassen.'),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(''),
                      child: const Text('Manuell eingeben'),
                    ),
                  ],
                ),
              ),
            )
          : controller == null || !controller.value.isInitialized
              ? const Center(
                  child: CircularProgressIndicator(color: GarantieHeldApp.emerald),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(controller),
                    const _ScannerGuide(),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 30,
                      child: Column(
                        children: [
                          const Text(
                            'Platziere den Kassenbon im Rahmen',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                            ),
                          ),
                          const SizedBox(height: 20),
                          FloatingActionButton.large(
                            heroTag: 'captureReceipt',
                            onPressed: _busy ? null : _captureAndRecognize,
                            backgroundColor: GarantieHeldApp.emerald,
                            foregroundColor: const Color(0xFF052E23),
                            child: _busy
                                ? const CircularProgressIndicator()
                                : const Icon(Icons.document_scanner_rounded, size: 32),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _ScannerGuide extends StatelessWidget {
  const _ScannerGuide();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          height: MediaQuery.of(context).size.height * 0.48,
          decoration: BoxDecoration(
            border: Border.all(color: GarantieHeldApp.emerald, width: 2),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}
