import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'database_helper.dart';
import 'gemini_receipt_analyzer.dart';
import 'receipt_ocr_parser.dart';
import 'warranty_model.dart';
import 'widgets/primary_button.dart';

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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: emerald, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFF87171)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFF87171), width: 1.5),
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
  final Set<String> _deletingWarrantyIds = {};
  final Set<String> _hiddenWarrantyIds = {};

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
    final scan = await Navigator.of(context).push<ReceiptOcrResult>(
      MaterialPageRoute(builder: (_) => const ReceiptScannerScreen()),
    );
    if (!mounted || scan == null) return;
    final warranty = await Navigator.of(context).push<Warranty>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WarrantyFormPage(scanResult: scan),
      ),
    );
    if (warranty == null || !mounted) return;
    await DatabaseHelper.instance.insertWarranty(warranty);
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    await _showSuccessOverlay();
  }

  Future<void> _openWarrantyDetails(Warranty warranty) async {
    final result = await Navigator.of(context).push<WarrantyDetailResult>(
      MaterialPageRoute(
        builder: (_) => WarrantyDetailPage(warranty: warranty),
      ),
    );
    if (!mounted || result == null) return;
    if (result.updatedWarranty != null) {
      await _refresh();
    } else if (result.deletedWarrantyId != null) {
      await _animateDeletedWarranty(result.deletedWarrantyId!);
    }
  }

  Future<void> _animateDeletedWarranty(String id) async {
    setState(() => _deletingWarrantyIds.add(id));
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    setState(() => _hiddenWarrantyIds.add(id));
    await _refresh();
    if (!mounted) return;
    setState(() {
      _deletingWarrantyIds.remove(id);
      _hiddenWarrantyIds.remove(id);
    });
  }

  Future<void> _showSuccessOverlay() async {
    final navigator = Navigator.of(context);
    ModalRoute<void>? overlayRoute;
    final overlay = showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Garantie gespeichert',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (dialogContext, _, __) {
        overlayRoute = ModalRoute.of(dialogContext);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 124,
                    height: 124,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: GarantieHeldApp.emerald.withValues(alpha: 0.14),
                      boxShadow: [
                        BoxShadow(
                          color: GarantieHeldApp.emerald.withValues(alpha: 0.42),
                          blurRadius: 42,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      size: 76,
                      color: GarantieHeldApp.emerald,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Garantie gesichert!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final bounce = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.72, end: 1).animate(bounce),
            child: child,
          ),
        );
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted && overlayRoute?.isCurrent == true) navigator.pop();
    await overlay;
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

          final warranties = (snapshot.data ?? const <Warranty>[])
              .where((item) => !_hiddenWarrantyIds.contains(item.id))
              .toList(growable: false);
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
                        ...warranties.map((item) {
                          final isDeleting = _deletingWarrantyIds.contains(item.id);
                          return TweenAnimationBuilder<double>(
                            key: ValueKey(item.id),
                            tween: Tween<double>(
                              begin: 1,
                              end: isDeleting ? 0 : 1,
                            ),
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.easeInOutCubic,
                            builder: (context, progress, child) => ClipRect(
                              child: Align(
                                alignment: Alignment.topCenter,
                                heightFactor: progress,
                                child: Opacity(opacity: progress, child: child),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: isDeleting
                                    ? null
                                    : () => _openWarrantyDetails(item),
                                child: _WarrantyCard(
                                  warranty: item,
                                  price: _currency.format(item.price),
                                  purchaseDate: _date.format(item.purchaseDate),
                                ),
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: PrimaryButton(
            label: 'Bon scannen',
            icon: Icons.document_scanner_outlined,
            onPressed: _addWarranty,
          ),
        ),
      ),
    );
  }
}

class WarrantyDetailResult {
  const WarrantyDetailResult({this.updatedWarranty, this.deletedWarrantyId});

  final Warranty? updatedWarranty;
  final String? deletedWarrantyId;
}

class WarrantyDetailPage extends StatefulWidget {
  const WarrantyDetailPage({super.key, required this.warranty});

  final Warranty warranty;

  @override
  State<WarrantyDetailPage> createState() => _WarrantyDetailPageState();
}

class _WarrantyDetailPageState extends State<WarrantyDetailPage> {
  bool _busy = false;

  Future<void> _editWarranty() async {
    final warranty = widget.warranty;
    final result = await Navigator.of(context).push<Warranty>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => WarrantyFormPage(
          warranty: warranty,
          scanResult: ReceiptOcrResult(
            fullText: '',
            productTitle: warranty.title,
            storeName: warranty.storeName,
            productPrice: warranty.price,
            purchaseDate: warranty.purchaseDate,
            category: warranty.category.name,
            imagePath: warranty.imagePath,
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    await DatabaseHelper.instance.updateWarranty(result);
    if (!mounted) return;
    Navigator.of(context).pop(WarrantyDetailResult(updatedWarranty: result));
  }

  Future<void> _deleteWarranty() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: GarantieHeldApp.surface,
        title: const Text('Garantie wirklich löschen?'),
        content: const Text('Diese Aktion kann nicht rückgängig gemacht werden.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFF87171)),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await DatabaseHelper.instance.deleteWarranty(widget.warranty.id);
    if (!mounted) return;
    Navigator.of(context).pop(
      WarrantyDetailResult(deletedWarrantyId: widget.warranty.id),
    );
  }

  Future<void> _exportReceipt() async {
    final imagePath = widget.warranty.imagePath;
    if (imagePath.isEmpty) {
      _showMessage('Für diese Garantie ist kein Belegfoto verfügbar.');
      return;
    }
    final imageExists = await File(imagePath).exists();
    if (!mounted) return;
    if (!imageExists) {
      _showMessage('Für diese Garantie ist kein Belegfoto verfügbar.');
      return;
    }
    final shouldExport = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: GarantieHeldApp.surface,
        title: const Text('Kassenbon speichern?'),
        content: const Text(
          'Möchtest du das Belegfoto in deinen Smartphone-Speicher / Galerie exportieren?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (shouldExport != true || !mounted) return;

    setState(() => _busy = true);
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        _showMessage('Der Zugriff auf die Galerie wurde nicht erlaubt.');
        return;
      }
      await Gal.putImage(imagePath, album: 'GarantieHeld');
      if (mounted) await _showExportSuccess();
    } catch (_) {
      _showMessage('Das Belegfoto konnte nicht gespeichert werden.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showExportSuccess() async {
    final navigator = Navigator.of(context);
    ModalRoute<void>? overlayRoute;
    final overlay = showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Kassenbon gespeichert',
      barrierColor: Colors.black.withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (dialogContext, _, __) {
        overlayRoute = ModalRoute.of(dialogContext);
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: GarantieHeldApp.emerald.withValues(alpha: 0.14),
                    boxShadow: [
                      BoxShadow(
                        color: GarantieHeldApp.emerald.withValues(alpha: 0.4),
                        blurRadius: 36,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.download_done_rounded,
                    color: GarantieHeldApp.emerald,
                    size: 68,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Kassenbon gespeichert!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted && overlayRoute?.isCurrent == true) navigator.pop();
    await overlay;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showReceiptFullscreen() async {
    final imagePath = widget.warranty.imagePath;
    if (imagePath.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Kassenbon'),
            leading: IconButton(
              tooltip: 'Schließen',
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Center(
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text(
                  'Belegfoto nicht verfügbar',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final warranty = widget.warranty;
    final date = DateFormat('dd.MM.yyyy', 'de_DE').format(warranty.purchaseDate);
    final price = NumberFormat.currency(locale: 'de_DE', symbol: '€').format(warranty.price);
    return Scaffold(
      backgroundColor: GarantieHeldApp.background,
      appBar: AppBar(
        title: Text(
          warranty.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: GarantieHeldApp.background,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: _WarrantyStatusBadge(isActive: !warranty.isExpired),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (warranty.imagePath.isNotEmpty) ...[
            Stack(
              children: [
                GestureDetector(
                  onTap: _showReceiptFullscreen,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.file(
                      File(warranty.imagePath),
                      height: 240,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 120,
                        child: Center(child: Text('Belegfoto nicht verfügbar')),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Material(
                    color: const Color.fromRGBO(0, 0, 0, 0.5),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Kassenbon auf Gerät speichern',
                      onPressed: _busy ? null : _exportReceipt,
                      icon: const Icon(Icons.download_rounded),
                      color: Colors.white,
                      iconSize: 24,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color.fromRGBO(0, 0, 0, 0.5),
                        fixedSize: const Size(48, 48),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 16,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(0, 0, 0, 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Text(
                          'Tippen zum Vergrößern',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          Text(
            warranty.title,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          _WarrantyDetailTile(label: 'Händler', value: warranty.storeName.isEmpty ? '—' : warranty.storeName),
          _WarrantyDetailTile(label: 'Kaufpreis', value: price),
          _WarrantyDetailTile(label: 'Kaufdatum', value: date),
          _WarrantyDetailTile(label: 'Kategorie', value: _categoryLabel(warranty.category)),
          _WarrantyDetailTile(label: 'Garantielaufzeit', value: '${warranty.warrantyMonths} Monate'),
          _WarrantyDetailTile(label: 'Garantieende', value: DateFormat('dd.MM.yyyy', 'de_DE').format(warranty.expirationDate)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Löschen',
                  icon: Icons.delete_outline_rounded,
                  tone: PrimaryButtonTone.destructive,
                  onPressed: _busy ? null : _deleteWarranty,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  label: 'Bearbeiten',
                  icon: Icons.edit_rounded,
                  onPressed: _busy ? null : _editWarranty,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarrantyDetailTile extends StatelessWidget {
  const _WarrantyDetailTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: GarantieHeldApp.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.62))),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _WarrantyStatusBadge extends StatefulWidget {
  const _WarrantyStatusBadge({required this.isActive});

  final bool isActive;

  @override
  State<_WarrantyStatusBadge> createState() => _WarrantyStatusBadgeState();
}

class _WarrantyStatusBadgeState extends State<_WarrantyStatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isActive
        ? GarantieHeldApp.emerald
        : const Color(0xFFF87171);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Opacity(
              opacity: widget.isActive ? 0.55 + (_controller.value * 0.45) : 1,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: color.withValues(alpha: 0.75), blurRadius: 6),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.isActive ? 'Aktiv' : 'Abgelaufen',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _categoryLabel(Category category) => switch (category) {
      Category.elektronik => 'Elektronik',
      Category.haushalt => 'Haushalt',
      Category.moebel => 'Möbel',
      Category.werkzeug => 'Werkzeug',
      Category.kleidung => 'Kleidung',
      Category.sonstiges => 'Sonstiges',
    };

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

class WarrantyFormPage extends StatefulWidget {
  const WarrantyFormPage({
    super.key,
    required this.scanResult,
    this.warranty,
  });

  final ReceiptOcrResult scanResult;
  final Warranty? warranty;

  @override
  State<WarrantyFormPage> createState() => _WarrantyFormPageState();
}

class _WarrantyFormPageState extends State<WarrantyFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  final _storeController = TextEditingController();
  final _priceController = TextEditingController();
  final _purchaseDateController = TextEditingController();
  late ReceiptOcrResult _scanResult;
  int _warrantyMonths = 24;
  Category _category = Category.elektronik;
  DateTime? _purchaseDate;
  bool _dateError = false;
  bool _isAnalyzing = false;
  bool _analysisRequestInProgress = false;
  String? _analysisError;

  @override
  void initState() {
    super.initState();
    final result = widget.scanResult;
    final existing = widget.warranty;
    _scanResult = result;
    _titleController = TextEditingController(
      text: existing?.title ?? result.productTitle,
    );
    _storeController.text = existing?.storeName ?? result.storeName;
    final initialPrice = existing?.price ?? result.productPrice;
    _priceController.text = initialPrice == null
        ? ''
        : initialPrice.toStringAsFixed(2).replaceAll('.', ',');
    _purchaseDate = existing?.purchaseDate ?? result.purchaseDate ?? DateTime.now();
    _category = existing?.category ?? _categoryFromGemini(result.category);
    _warrantyMonths = existing?.warrantyMonths ?? 24;
    _purchaseDateController.text = DateFormat('dd.MM.yyyy').format(_purchaseDate!);
    _isAnalyzing = existing == null && result.imagePath.isNotEmpty;
    if (_isAnalyzing) unawaited(_analyzeReceipt());
  }

  Future<void> _analyzeReceipt() async {
    if (_analysisRequestInProgress) return;
    _analysisRequestInProgress = true;
    try {
      if (kDebugMode) {
        debugPrint(
          '[Gemini] wizard analysis started | model=$geminiModelName | '
          'apiKeyConfigured=${GeminiReceiptAnalyzer.hasApiKey}',
        );
      }
      final result = await GeminiReceiptAnalyzer.analyzeReceipt(
        imagePath: _scanResult.imagePath,
      );
      if (!mounted) return;
      setState(() {
        _scanResult = result;
        _titleController.text = result.productTitle;
        _storeController.text = result.storeName;
        _priceController.text = result.productPrice == null
            ? ''
            : result.productPrice!.toStringAsFixed(2).replaceAll('.', ',');
        _purchaseDate = result.purchaseDate ?? _purchaseDate;
        _purchaseDateController.text = _purchaseDate == null
            ? ''
            : DateFormat('dd.MM.yyyy').format(_purchaseDate!);
        _category = _categoryFromGemini(result.category);
        _isAnalyzing = false;
        _analysisError = null;
      });
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          '[Gemini] wizard analysis failed: ${GeminiReceiptAnalyzer.diagnosticFor(error)}',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
        _analysisError = !GeminiReceiptAnalyzer.hasApiKey
            ? 'Gemini-API-Key fehlt. Starte mit --dart-define=GEMINI_API_KEY=…'
            : GeminiReceiptAnalyzer.isServiceUnavailable(error)
                ? 'Gemini ist momentan stark ausgelastet (HTTP 503).'
                : error is TimeoutException
                    ? 'Die KI-Analyse hat zu lange gedauert.'
                    : 'Die KI-Analyse ist fehlgeschlagen.';
      });
    } finally {
      _analysisRequestInProgress = false;
    }
  }

  void _retryAnalysis() {
    setState(() {
      _isAnalyzing = true;
      _analysisError = null;
    });
    unawaited(_analyzeReceipt());
  }

  Category _categoryFromGemini(String value) => switch (value.trim().toLowerCase()) {
        'elektronik' => Category.elektronik,
        'haushalt' => Category.haushalt,
        'möbel' || 'moebel' => Category.moebel,
        'werkzeug' => Category.werkzeug,
        'kleidung' => Category.kleidung,
        _ => Category.sonstiges,
      };

  @override
  void dispose() {
    _titleController.dispose();
    _storeController.dispose();
    _priceController.dispose();
    _purchaseDateController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (_purchaseDate == null) {
      setState(() => _dateError = true);
      return;
    }
    final warranty = Warranty(
      id: widget.warranty?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      storeName: _storeController.text.trim(),
      price: double.parse(_priceController.text.trim().replaceAll(',', '.')),
      purchaseDate: _purchaseDate!,
      warrantyMonths: _warrantyMonths,
      category: _category,
      imagePath: _scanResult.imagePath,
      serialNumber: widget.warranty?.serialNumber,
      notes: widget.warranty?.notes,
      reminderDaysBefore: widget.warranty?.reminderDaysBefore ?? 30,
    );
    Navigator.of(context).pop(warranty);
  }

  Future<void> _selectPurchaseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );
    if (selected == null) return;
    setState(() {
      _purchaseDate = selected;
      _purchaseDateController.text = DateFormat('dd.MM.yyyy').format(selected);
      _dateError = false;
    });
  }

  Widget _purchaseDateActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Datum auswählen',
          onPressed: _selectPurchaseDate,
          icon: const Icon(Icons.calendar_month_rounded),
        ),
        if (_purchaseDateController.text.isNotEmpty)
          IconButton(
            tooltip: 'Datum leeren',
            onPressed: () {
              setState(() {
                _purchaseDate = null;
                _purchaseDateController.clear();
                _dateError = false;
              });
            },
            icon: const Icon(Icons.clear),
          ),
      ],
    );
  }

  Future<void> _showReceiptPreview() async {
    final imagePath = _scanResult.imagePath;
    if (imagePath.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Kassenbon'),
            leading: IconButton(
              tooltip: 'Schließen',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          body: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text(
                  'Kassenbon-Bild nicht verfügbar',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _clearButton(TextEditingController controller) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => value.text.isEmpty
          ? const SizedBox.shrink()
          : IconButton(
              tooltip: 'Feld leeren',
              onPressed: controller.clear,
              icon: const Icon(Icons.clear),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const availableMonths = [12, 24, 36];
    return Scaffold(
      backgroundColor: GarantieHeldApp.background,
      appBar: AppBar(
        backgroundColor: GarantieHeldApp.background,
        leading: IconButton(
          tooltip: 'Zurück',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Garantie bestätigen',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(
              child: Text(
                'Schritt 2/2',
                style: TextStyle(color: Colors.white.withOpacity(0.56), fontSize: 12),
              ),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFF263449)),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: GarantieHeldApp.surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            color: GarantieHeldApp.emerald,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'FAST GESCHAFFT!',
                                style: TextStyle(
                                  color: GarantieHeldApp.emerald,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Dein Beleg wurde erfasst',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (_scanResult.imagePath.isNotEmpty) ...[
                      Center(
                        child: GestureDetector(
                          onTap: _showReceiptPreview,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(_scanResult.imagePath),
                              height: 180,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 180,
                                width: double.infinity,
                                alignment: Alignment.center,
                                color: GarantieHeldApp.surface,
                                child: const Text('Kassenbon-Bild nicht verfügbar'),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Tippen zum Vergrößern',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.52),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (_isAnalyzing) ...[
                      const _GeminiAnalysisCard(
                        title: 'KI analysiert Kassenbon...',
                        subtitle: 'Produkt, Einzelpreis, Händler und Datum werden erkannt.',
                      ),
                    ] else ...[
                      if (_analysisError != null) ...[
                        _GeminiAnalysisErrorCard(
                          message: _analysisError!,
                          onRetry: _retryAnalysis,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_scanResult.productPrice == null ||
                          _scanResult.purchaseDate == null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A321D),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Nicht alles wurde erkannt. Ergänze die fehlenden Angaben.',
                          style: TextStyle(color: Color(0xFFFBBF24), fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    const _WizardFieldLabel('Produktname'),
                    TextFormField(
                      controller: _titleController,
                      autofocus: _titleController.text.isEmpty,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _wizardInputDecoration(
                        hintText: 'z. B. MOBILE ENERGIESTATION',
                        suffixIcon: _clearButton(_titleController),
                      ),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Bitte Produktname eingeben'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final sideBySide = constraints.maxWidth >= 560;
                        final storeField = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _WizardFieldLabel('Händler'),
                            TextFormField(
                              controller: _storeController,
                              textCapitalization: TextCapitalization.words,
                              decoration: _wizardInputDecoration(
                                hintText: 'Händlername',
                                suffixIcon: _clearButton(_storeController),
                              ),
                            ),
                          ],
                        );
                        final priceField = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _WizardFieldLabel('Kaufpreis (€)'),
                            TextFormField(
                              controller: _priceController,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: _wizardInputDecoration(
                                hintText: '0,00',
                                suffixIcon: _clearButton(_priceController),
                              ),
                              validator: (value) {
                                final parsed = double.tryParse(
                                  (value ?? '').trim().replaceAll(',', '.'),
                                );
                                return parsed == null ||
                                        !parsed.isFinite ||
                                        parsed < 0
                                    ? 'Ungültiger Preis'
                                    : null;
                              },
                            ),
                          ],
                        );
                        if (sideBySide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: storeField),
                              const SizedBox(width: 14),
                              Expanded(child: priceField),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            storeField,
                            const SizedBox(height: 16),
                            priceField,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const _WizardFieldLabel('Kaufdatum'),
                    TextFormField(
                      controller: _purchaseDateController,
                      readOnly: true,
                      onTap: _selectPurchaseDate,
                      decoration: _wizardInputDecoration(
                        hintText: 'Datum auswählen',
                        errorText: _dateError ? 'Bitte Kaufdatum auswählen' : null,
                        suffixIcon: _purchaseDateActions(),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const _WizardFieldLabel('Garantie-Laufzeit'),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final months in availableMonths) ...[
                            _WarrantyDurationPill(
                              months: months,
                              selected: _warrantyMonths == months,
                              onTap: () => setState(() => _warrantyMonths = months),
                            ),
                            if (months != availableMonths.last)
                              const SizedBox(width: 10),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _WizardFieldLabel('Garantie-Kategorie'),
                    DropdownButtonFormField<Category>(
                      value: _category,
                      decoration: _wizardInputDecoration(
                        hintText: 'Kategorie auswählen',
                      ),
                      items: Category.values
                          .map((category) => DropdownMenuItem(
                                value: category,
                                child: Text(_categoryLabel(category)),
                              ))
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _category = value ?? _category),
                    ),
                    const SizedBox(height: 16),
                    const _WizardFieldLabel('Weitere Laufzeit'),
                    DropdownButtonFormField<int>(
                      value: _warrantyMonths,
                      decoration: _wizardInputDecoration(
                        hintText: 'Monate auswählen',
                      ),
                      items: const [12, 24, 36, 48, 60]
                          .map((months) => DropdownMenuItem(
                                value: months,
                                child: Text('$months Monate'),
                              ))
                          .toList(),
                      onChanged: (value) => setState(
                        () => _warrantyMonths = value ?? _warrantyMonths,
                      ),
                    ),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              bottom: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
                child: PrimaryButton(
                  label: widget.warranty == null
                      ? 'GARANTIE JETZT SICHERN'
                      : 'ÄNDERUNGEN SPEICHERN',
                  icon: Icons.shield_rounded,
                  onPressed: _isAnalyzing ? null : _save,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _wizardInputDecoration({
    required String hintText,
    Widget? suffixIcon,
    String? errorText,
  }) => InputDecoration(
        hintText: hintText,
        errorText: errorText,
        filled: true,
        fillColor: GarantieHeldApp.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: GarantieHeldApp.emerald, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFF87171)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFF87171), width: 1.5),
        ),
      );

  String _categoryLabel(Category category) => switch (category) {
        Category.elektronik => 'Elektronik',
        Category.haushalt => 'Haushalt',
        Category.moebel => 'Möbel',
        Category.werkzeug => 'Werkzeug',
        Category.kleidung => 'Kleidung',
        Category.sonstiges => 'Sonstiges',
      };
}

class _GeminiAnalysisCard extends StatelessWidget {
  const _GeminiAnalysisCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: GarantieHeldApp.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: GarantieHeldApp.emerald,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _GeminiAnalysisErrorCard extends StatelessWidget {
  const _GeminiAnalysisErrorCard({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF35232A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded, color: Color(0xFFFCA5A5)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$message Du kannst die Felder manuell ausfüllen.',
                  style: const TextStyle(color: Color(0xFFFECACA)),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Erneut versuchen'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WizardFieldLabel extends StatelessWidget {
  const _WizardFieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFFD6E0ED),
        ),
      ),
    );
  }
}

class _WarrantyDurationPill extends StatelessWidget {
  const _WarrantyDurationPill({
    required this.months,
    required this.selected,
    required this.onTap,
  });

  final int months;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$months Monate Garantie',
      child: Material(
        color: selected ? GarantieHeldApp.emerald : GarantieHeldApp.surface,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              '$months Monate',
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFFCBD5E1),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReceiptScannerScreen extends StatefulWidget {
  const ReceiptScannerScreen({super.key});

  @override
  State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State<ReceiptScannerScreen> {
  CameraController? _controller;
  final ImagePicker _imagePicker = ImagePicker();
  String? _error;
  bool _busy = false;
  bool _flashEnabled = false;
  bool _canOpenSettings = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      var permission = await Permission.camera.status;
      if (!permission.isGranted) {
        permission = await Permission.camera.request();
      }
      if (!permission.isGranted) {
        if (mounted) {
          setState(() {
            _canOpenSettings = permission.isPermanentlyDenied || permission.isRestricted;
            _error = _canOpenSettings
                ? 'Kamerazugriff ist gesperrt. Erlaube ihn in den App-Einstellungen.'
                : 'Für den Bon-Scan wird Kamerazugriff benötigt.';
          });
        }
        return;
      }

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
    if (kDebugMode) {
      debugPrint(
        '[Gemini] model=$geminiModelName, apiKeyConfigured=${GeminiReceiptAnalyzer.hasApiKey}',
      );
    }
    setState(() => _busy = true);
    try {
      final image = await controller.takePicture();
      var imagePath = image.path;
      try {
        imagePath = await _persistReceiptImage(image.path);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Das Foto bleibt vorerst nur temporär verfügbar.'),
            ),
          );
        }
      }

      if (identical(_controller, controller)) _controller = null;
      await controller.dispose();
      if (mounted) {
        Navigator.of(context).pop(
          ReceiptOcrParser.parse('', imagePath: imagePath),
        );
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

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    final enableFlash = !_flashEnabled;
    try {
      await controller.setFlashMode(enableFlash ? FlashMode.always : FlashMode.off);
      if (mounted) setState(() => _flashEnabled = enableFlash);
    } on CameraException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.description ?? 'Blitz konnte nicht geändert werden.')),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      var imagePath = image.path;
      try {
        imagePath = await _persistReceiptImage(image.path);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Das Bild bleibt vorerst nur temporär verfügbar.')),
          );
        }
      }

      final controller = _controller;
      _controller = null;
      await controller?.dispose();
      if (mounted) {
        Navigator.of(context).pop(ReceiptOcrParser.parse('', imagePath: imagePath));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Das Foto konnte nicht aus der Galerie geladen werden.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continueManually() {
    if (_busy) return;
    Navigator.of(context).pop(ReceiptOcrParser.parse(''));
  }

  Future<String> _persistReceiptImage(String sourcePath) async {
    final documents = await getApplicationDocumentsDirectory();
    final receiptsDirectory = Directory(path.join(documents.path, 'receipts'));
    await receiptsDirectory.create(recursive: true);
    final extension = path.extension(sourcePath).isEmpty
        ? '.jpg'
        : path.extension(sourcePath);
    final destination = path.join(
      receiptsDirectory.path,
      'receipt_${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    return (await File(sourcePath).copy(destination)).path;
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
        titleSpacing: 0,
        title: const Text('Bon scannen'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: _flashEnabled ? 'Blitz ausschalten' : 'Blitz einschalten',
            onPressed: controller == null || !controller.value.isInitialized || _busy
                ? null
                : _toggleFlash,
            icon: Icon(_flashEnabled ? Icons.flash_on : Icons.flash_off),
          ),
          IconButton(
            tooltip: 'Foto aus Galerie laden',
            onPressed: _busy ? null : _pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'Schritt 1/2',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.56),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
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
                      onPressed: () => Navigator.of(context).pop(
                        ReceiptOcrParser.parse(''),
                      ),
                      child: const Text('Manuell eingeben'),
                    ),
                    if (_canOpenSettings) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: openAppSettings,
                        icon: const Icon(Icons.settings_outlined),
                        label: const Text('Einstellungen öffnen'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : controller == null || !controller.value.isInitialized
              ? const Center(
                  child: CircularProgressIndicator(color: GarantieHeldApp.emerald),
                )
              : _buildCameraScanner(controller),
    );
  }

  Widget _buildCameraScanner(CameraController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final guideWidth = constraints.maxWidth * 0.86;
        final guideHeight = constraints.maxHeight * 0.60;
        final guideRect = Rect.fromCenter(
          center: Offset(constraints.maxWidth / 2, constraints.maxHeight * 0.32),
          width: guideWidth,
          height: guideHeight,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            _buildFullScreenPreview(controller, constraints.biggest),
            Positioned.fill(
              child: CustomPaint(
                painter: _ScannerShadePainter(guideRect: guideRect),
              ),
            ),
            Positioned.fromRect(
              rect: guideRect,
              child: const _ScannerGuide(),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 0,
              child: SafeArea(
                top: false,
                bottom: true,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                      const SizedBox(height: 8),
                      Text(
                        'Das Bonfoto wird zur KI-Analyse an Google gesendet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FloatingActionButton.large(
                        heroTag: 'captureReceipt',
                        onPressed: _busy ? null : _captureAndRecognize,
                        backgroundColor: GarantieHeldApp.emerald,
                        foregroundColor: const Color(0xFF052E23),
                        child: _busy
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.document_scanner_rounded, size: 32),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _continueManually,
                        icon: const Icon(Icons.edit_note_rounded, size: 19),
                        label: const Text('Manuell eingeben  →'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0x991E293B),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xB30F172A),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 28),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                      decoration: BoxDecoration(
                        color: GarantieHeldApp.surface,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 28,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: GarantieHeldApp.emerald,
                            ),
                          ),
                          SizedBox(width: 16),
                          Flexible(
                            child: Text(
                              'Foto wird gespeichert...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFullScreenPreview(CameraController controller, Size viewport) {
    final isLandscape = viewport.width >= viewport.height;
    final aspectRatio = isLandscape
        ? controller.value.aspectRatio
        : 1 / controller.value.aspectRatio;
    const previewHeight = 1000.0;

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: previewHeight * aspectRatio,
            height: previewHeight,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _ScannerGuide extends StatelessWidget {
  const _ScannerGuide();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _ScannerCornersPainter()),
    );
  }
}

class _ScannerShadePainter extends CustomPainter {
  const _ScannerShadePainter({required this.guideRect});

  final Rect guideRect;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(guideRect, const Radius.circular(20)));
    canvas.drawPath(
      shade,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerShadePainter oldDelegate) =>
      oldDelegate.guideRect != guideRect;
}

class _ScannerCornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cornerLength = 30.0;
    const inset = 2.0;
    final paint = Paint()
      ..color = GarantieHeldApp.emerald
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(inset, cornerLength)
      ..lineTo(inset, inset + 20)
      ..quadraticBezierTo(inset, inset, inset + 20, inset)
      ..lineTo(cornerLength, inset)
      ..moveTo(size.width - cornerLength, inset)
      ..lineTo(size.width - inset - 20, inset)
      ..quadraticBezierTo(size.width - inset, inset, size.width - inset, inset + 20)
      ..lineTo(size.width - inset, cornerLength)
      ..moveTo(size.width - inset, size.height - cornerLength)
      ..lineTo(size.width - inset, size.height - inset - 20)
      ..quadraticBezierTo(
        size.width - inset,
        size.height - inset,
        size.width - inset - 20,
        size.height - inset,
      )
      ..lineTo(size.width - cornerLength, size.height - inset)
      ..moveTo(cornerLength, size.height - inset)
      ..lineTo(inset + 20, size.height - inset)
      ..quadraticBezierTo(inset, size.height - inset, inset, size.height - inset - 20)
      ..lineTo(inset, size.height - cornerLength);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerCornersPainter oldDelegate) => false;
}

