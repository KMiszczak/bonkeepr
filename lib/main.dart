import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute, kDebugMode;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import 'database_helper.dart';
import 'gemini_receipt_analyzer.dart';
import 'notification_service.dart';
import 'receipt_ocr_parser.dart';
import 'settings_screen.dart';
import 'theme_controller.dart';
import 'warranty_model.dart';
import 'widgets/primary_button.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  await ThemeController.instance.load();
  runApp(const GarantieHeldApp());
}

class GarantieHeldApp extends StatelessWidget {
  const GarantieHeldApp({super.key});

  static const emerald = Color(0xFF10B981);
  static const background = Color(0xFF0F172A);
  static const surface = Color(0xFF1E293B);
  static Color surfaceFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? surface : Colors.white;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: ThemeController.instance,
    builder: (context, _) {
      ThemeData buildTheme(bool dark) => ThemeData(
        useMaterial3: true,
        brightness: dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: dark ? background : const Color(0xFFF1F5F9),
        colorScheme: dark
            ? const ColorScheme.dark(
                primary: emerald,
                secondary: Color(0xFF34D399),
                surface: surface,
                error: Color(0xFFF87171),
              )
            : const ColorScheme.light(
                primary: emerald,
                secondary: Color(0xFF059669),
                surface: Colors.white,
                error: Color(0xFFDC2626),
              ),
        fontFamily: 'Roboto',
      );
      final darkTheme = buildTheme(true);
      final lightTheme = buildTheme(false);
      return MaterialApp(
        title: 'GarantieHeld',
        debugShowCheckedModeBanner: false,
        theme: lightTheme.copyWith(
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF1F5F9),
            foregroundColor: Color(0xFF0F172A),
            elevation: 0,
          ),
          inputDecorationTheme: lightTheme.inputDecorationTheme,
        ),
        darkTheme: darkTheme.copyWith(
          appBarTheme: const AppBarTheme(
            backgroundColor: background,
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
        themeMode: ThemeController.instance.themeMode,
        home: const DashboardScreen(),
      );
    },
  );
}

Future<void> _shareWarrantyData(BuildContext context, Warranty warranty) async {
  final purchaseDate = DateFormat(
    'dd.MM.yyyy',
    'de_DE',
  ).format(warranty.purchaseDate);
  final expirationDate = DateFormat(
    'dd.MM.yyyy',
    'de_DE',
  ).format(warranty.expirationDate);
  final price = '${NumberFormat('#,##0.00', 'de_DE').format(warranty.price)} €';
  final text =
      '''📄 BonKeepr Beleg-Export

Produkt: ${warranty.title}
Händler: ${warranty.storeName.isEmpty ? '—' : warranty.storeName}
Kaufpreis: $price
Kaufdatum: $purchaseDate
Garantie bis: $expirationDate

Gesichert mit BonKeepr 🛡️''';
  try {
    final filePath = warranty.imagePath;
    final files = filePath.isNotEmpty && await File(filePath).exists()
        ? [XFile(filePath)]
        : <XFile>[];
    await SharePlus.instance.share(ShareParams(text: text, files: files));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Der Beleg konnte nicht geteilt werden.')),
      );
    }
  }
}

class _ReceiptCarouselDialog extends StatefulWidget {
  const _ReceiptCarouselDialog({
    required this.receiptPaths,
    this.initialPage = 0,
  });

  final List<String> receiptPaths;
  final int initialPage;

  @override
  State<_ReceiptCarouselDialog> createState() => _ReceiptCarouselDialogState();
}

class _ReceiptCarouselDialogState extends State<_ReceiptCarouselDialog> {
  late final PageController _pageController;
  late int _currentPage;
  final Map<String, int> _pendingRotationAngles = {};
  final Set<String> _rotatedImagePaths = {};
  bool _rotationInProgress = false;
  bool _allowViewerPop = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
    _pageController = PageController(initialPage: widget.initialPage);
  }

  Future<void> _rotateCurrentReceipt(int angle) async {
    if (_rotationInProgress) return;
    final mediaPath = widget.receiptPaths[_currentPage];
    if (_isPdfPath(mediaPath)) return;
    final currentAngle = _pendingRotationAngles[mediaPath] ?? 0;
    final nextAngle = ((currentAngle + angle) % 360 + 360) % 360;
    setState(() {
      _rotationInProgress = true;
      _pendingRotationAngles[mediaPath] = nextAngle;
    });
    try {
      final file = File(mediaPath);
      final decoded = img.decodeImage(await file.readAsBytes());
      if (decoded == null) throw const FormatException('Ungültiges Bild.');
      final upright = img.bakeOrientation(decoded);
      final rotated = _resizeReceiptImage(
        img.copyRotate(upright, angle: angle),
      );
      final bytes = mediaPath.toLowerCase().endsWith('.png')
          ? img.encodePng(rotated)
          : img.encodeJpg(rotated, quality: 82);
      await file.writeAsBytes(bytes, flush: true);
      await FileImage(file).evict();
      if (mounted) {
        setState(() {
          _pendingRotationAngles.remove(mediaPath);
          _rotationInProgress = false;
          _rotatedImagePaths.add(mediaPath);
        });
      }
    } catch (_) {
      if (!mounted) return;
      await FileImage(File(mediaPath)).evict();
      if (!mounted) return;
      setState(() {
        _pendingRotationAngles.remove(mediaPath);
        _rotationInProgress = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Belegfoto konnte nicht gedreht werden.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _closeViewer() async {
    if (_rotationInProgress) return;
    if (!_allowViewerPop) {
      setState(() => _allowViewerPop = true);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    Navigator.of(context).pop(_rotatedImagePaths.toList(growable: false));
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: PopScope<List<String>>(
      canPop: _allowViewerPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_closeViewer());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Belege'),
          leading: IconButton(
            tooltip: 'Schließen',
            onPressed: _rotationInProgress ? null : _closeViewer,
            icon: const Icon(Icons.close),
          ),
        ),
        body: SafeArea(
          bottom: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.receiptPaths.length,
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  itemBuilder: (context, index) {
                    final mediaPath = widget.receiptPaths[index];
                    if (_isPdfPath(mediaPath)) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: Color(0xFFF87171),
                              size: 72,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'PDF-Beleg',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () => OpenFilex.open(mediaPath),
                              icon: const Icon(Icons.open_in_new_rounded),
                              label: const Text('Mit Standard-App öffnen'),
                            ),
                          ],
                        ),
                      );
                    }
                    return InteractiveViewer(
                      panEnabled: false,
                      minScale: 1,
                      maxScale: 6,
                      child: Center(
                        child: Builder(
                          builder: (context) {
                            final rotationAngle =
                                _pendingRotationAngles[mediaPath] ?? 0;
                            return Transform.rotate(
                              angle: rotationAngle * math.pi / 180,
                              child: Image.file(
                                File(mediaPath),
                                key: ValueKey('${mediaPath}_$rotationAngle'),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Text(
                                  'Belegfoto nicht verfügbar',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                left: 32,
                right: 32,
                bottom: 28,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _rotationButton(
                      tooltip: 'Nach links drehen',
                      icon: Icons.rotate_left,
                      onPressed:
                          _rotationInProgress ||
                              _isPdfPath(widget.receiptPaths[_currentPage])
                          ? null
                          : () => _rotateCurrentReceipt(-90),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        '${_currentPage + 1}/${widget.receiptPaths.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _rotationButton(
                      tooltip: 'Nach rechts drehen',
                      icon: Icons.rotate_right,
                      onPressed:
                          _rotationInProgress ||
                              _isPdfPath(widget.receiptPaths[_currentPage])
                          ? null
                          : () => _rotateCurrentReceipt(90),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _rotationButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => Container(
    decoration: const BoxDecoration(
      color: Colors.black45,
      shape: BoxShape.circle,
    ),
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      color: Colors.white,
      icon: Icon(icon),
    ),
  );
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

enum _WarrantySort { expiration, purchase, price, name, merchant }

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<Warranty>> _warrantiesFuture;
  final _currency = NumberFormat.currency(locale: 'de_DE', symbol: '€');
  final _date = DateFormat('dd.MM.yyyy', 'de_DE');
  final _searchController = TextEditingController();
  final Set<String> _deletingWarrantyIds = {};
  final Set<String> _hiddenWarrantyIds = {};
  String _searchQuery = '';
  _WarrantySort _sort = _WarrantySort.expiration;

  void _sortWarranties(List<Warranty> items) {
    items.sort(
      (a, b) => switch (_sort) {
        _WarrantySort.expiration => a.expirationDate.compareTo(
          b.expirationDate,
        ),
        _WarrantySort.purchase => b.purchaseDate.compareTo(a.purchaseDate),
        _WarrantySort.price => b.price.compareTo(a.price),
        _WarrantySort.name => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
        _WarrantySort.merchant => a.storeName.toLowerCase().compareTo(
          b.storeName.toLowerCase(),
        ),
      },
    );
  }

  Future<void> _showSortOptions() async {
    final selected = await showModalBottomSheet<_WarrantySort>(
      context: context,
      backgroundColor: GarantieHeldApp.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Sortieren nach',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              for (final option in _WarrantySort.values)
                ListTile(
                  leading: Text(switch (option) {
                    _WarrantySort.expiration => '⏳',
                    _WarrantySort.purchase => '📅',
                    _WarrantySort.price => '💰',
                    _WarrantySort.name => '🔤',
                    _WarrantySort.merchant => '🏪',
                  }, style: const TextStyle(fontSize: 19)),
                  title: Text(switch (option) {
                    _WarrantySort.expiration =>
                      'Ablaufdatum (Dringendste zuerst)',
                    _WarrantySort.purchase => 'Kaufdatum (Neueste zuerst)',
                    _WarrantySort.price => 'Preis (Höchster zuerst)',
                    _WarrantySort.name => 'Name (A bis Z)',
                    _WarrantySort.merchant => 'Händler (A bis Z)',
                  }),
                  trailing: _sort == option
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'AKTIV',
                              style: TextStyle(
                                color: GarantieHeldApp.emerald,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.check_circle,
                              color: GarantieHeldApp.emerald,
                            ),
                          ],
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(option),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _sort = selected);
  }

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final scheduled = await NotificationService.scheduleWarrantyReminder(
      warranty,
    );
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    if (!scheduled && warranty.reminderDaysBefore >= 0) {
      _showNotificationPermissionHint();
    }
    await _showSuccessOverlay();
  }

  Future<void> _openWarrantyDetails(Warranty warranty) async {
    final result = await Navigator.of(context).push<WarrantyDetailResult>(
      MaterialPageRoute(builder: (_) => WarrantyDetailPage(warranty: warranty)),
    );
    if (!mounted || result == null) return;
    if (result.updatedWarranty != null) {
      await NotificationService.scheduleWarrantyReminder(
        result.updatedWarranty!,
      );
      await _refresh();
    } else if (result.deletedWarrantyId != null) {
      await NotificationService.cancelWarrantyReminder(
        result.deletedWarrantyId!,
      );
      await _animateDeletedWarranty(result.deletedWarrantyId!);
    }
  }

  Future<void> _previewWarrantyReceipt(Warranty warranty) async {
    final receiptPaths = <String>[];
    for (final receiptPath in warranty.allReceiptPaths.take(3)) {
      if (receiptPath.isNotEmpty && await File(receiptPath).exists()) {
        receiptPaths.add(receiptPath);
      }
    }
    if (receiptPaths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belegdatei nicht verfügbar.')),
        );
      }
      return;
    }
    if (receiptPaths.length == 1 && _isPdfPath(receiptPaths.single)) {
      await OpenFilex.open(receiptPaths.single);
      return;
    }
    if (!mounted) return;
    final rotatedPaths = await showDialog<List<String>>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => _ReceiptCarouselDialog(receiptPaths: receiptPaths),
    );
    if (!mounted) return;
    await _evictReceiptImageCache(rotatedPaths ?? receiptPaths);
    if (mounted) await _refresh();
  }

  Future<void> _editWarrantyFromCard(Warranty warranty) async {
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
    final scheduled = await NotificationService.scheduleWarrantyReminder(
      result,
    );
    if (!mounted) return;
    await _refresh();
    if (!scheduled && result.reminderDaysBefore >= 0) {
      _showNotificationPermissionHint();
    }
  }

  void _showNotificationPermissionHint() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Erinnerung konnte nicht geplant werden. Bitte Benachrichtigungen erlauben.',
        ),
      ),
    );
  }

  Future<void> _deleteWarrantyFromCard(Warranty warranty) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: GarantieHeldApp.surface,
        title: const Text('Garantie wirklich löschen?'),
        content: const Text(
          'Diese Aktion kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF87171),
            ),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await DatabaseHelper.instance.deleteWarranty(warranty.id);
    await NotificationService.cancelWarrantyReminder(warranty.id);
    if (mounted) await _animateDeletedWarranty(warranty.id);
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
                          color: GarantieHeldApp.emerald.withValues(
                            alpha: 0.42,
                          ),
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

  Future<void> _showInfoSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BonKeeprInfoSheet(),
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Image.asset(
                'assets/bonkeeprlogotransparent.png',
                height: 32,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 10),
              const Text(
                'BonKeepr',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Über BonKeepr',
              onPressed: _showInfoSheet,
              icon: const Icon(Icons.info_outline),
              color: GarantieHeldApp.emerald,
            ),
            IconButton(
              tooltip: 'Einstellungen',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    onDataImported: _refresh,
                    onThemeModeChanged: ThemeController.instance.setThemeMode,
                  ),
                ),
              ),
              icon: const Icon(Icons.settings_outlined),
              color: GarantieHeldApp.emerald,
            ),
          ],
        ),
        extendBody: true,
        body: FutureBuilder<List<Warranty>>(
          future: _warrantiesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                  color: GarantieHeldApp.emerald,
                ),
              );
            }
            if (snapshot.hasError) return _LoadError(onRetry: _refresh);

            final warranties = (snapshot.data ?? const <Warranty>[])
                .where((item) => !_hiddenWarrantyIds.contains(item.id))
                .toList(growable: false);
            final query = _searchQuery.trim().toLowerCase();
            final filteredWarranties = warranties.where((item) {
              return query.isEmpty ||
                  item.title.toLowerCase().contains(query) ||
                  item.storeName.toLowerCase().contains(query);
            }).toList();
            _sortWarranties(filteredWarranties);
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
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 150),
                    sliver: SliverList.list(
                      children: [
                        _ProtectedValueCard(
                          amount: _currency.format(protectedTotal),
                          activeCount: active.length,
                          expiringCount: expiring,
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _searchController,
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Garantie oder Händler suchen...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon:
                                ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _searchController,
                                  builder: (context, value, _) =>
                                      value.text.isEmpty
                                      ? const SizedBox.shrink()
                                      : IconButton(
                                          tooltip: 'Suche leeren',
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                          icon: const Icon(Icons.clear_rounded),
                                        ),
                                ),
                            filled: true,
                            fillColor: GarantieHeldApp.surfaceFor(context),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 15,
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
                              borderSide: const BorderSide(
                                color: GarantieHeldApp.emerald,
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Deine Garantien (${filteredWarranties.length})',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: _showSortOptions,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF334155),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Sortieren',
                                      style: TextStyle(
                                        color: Color(0xFFE2E8F0),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 16,
                                      color: Color(0xFFE2E8F0),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (warranties.isEmpty)
                          const _EmptyState()
                        else if (filteredWarranties.isEmpty)
                          const _SearchEmptyState()
                        else
                          ...filteredWarranties.map((item) {
                            final isDeleting = _deletingWarrantyIds.contains(
                              item.id,
                            );
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
                                  child: Opacity(
                                    opacity: progress,
                                    child: child,
                                  ),
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
                                    purchaseDate: _date.format(
                                      item.purchaseDate,
                                    ),
                                    onShare: () =>
                                        _shareWarrantyData(context, item),
                                    onDetails: () => _openWarrantyDetails(item),
                                    onPreview: () =>
                                        _previewWarrantyReceipt(item),
                                    onEdit: () => _editWarrantyFromCard(item),
                                    onDelete: () =>
                                        _deleteWarrantyFromCard(item),
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
        bottomNavigationBar: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            GarantieHeldApp.background.withValues(alpha: 0.82),
                            GarantieHeldApp.background,
                          ],
                          stops: const [0, 0.38, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: PrimaryButton(
                  label: 'Bon scannen',
                  icon: Icons.document_scanner_outlined,
                  onPressed: _addWarranty,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BonKeeprInfoSheet extends StatelessWidget {
  const _BonKeeprInfoSheet();

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.84,
      child: Material(
        color: GarantieHeldApp.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.34),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/bonkeeprlogotransparent.png',
                        height: 80,
                        fit: BoxFit.contain,
                      ),
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Willkommen bei BonKeepr 🛡️',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Deine digitale Garage für Garantien & Kassenbons.',
                      style: TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF263449)),
              const Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 10, 24, 10),
                  child: Column(
                    children: [
                      _InfoFeature(
                        icon: Icons.auto_awesome_rounded,
                        text:
                            'KI-Erkennung: Fotografiere deinen Beleg – Händler, Preis & Datum werden automatisch erfasst.',
                      ),
                      _InfoFeature(
                        icon: Icons.edit_note_rounded,
                        text:
                            'Manuelle Eingabe & Datenschutz: Kein KI-Fan? Du kannst alle Belege und Garantien auch vollständig manuell erfassen. Es werden dann keinerlei Daten an eine KI gesendet.',
                      ),
                      _InfoFeature(
                        icon: Icons.schedule_rounded,
                        text:
                            'Garantie-Scanner: Behalte die Ablaufdaten deiner Geräte immer im Blick.',
                      ),
                      _InfoFeature(
                        icon: Icons.lock_outline_rounded,
                        text:
                            '100% Datensicherheit: Deine Daten gehören dir. Standardmäßig komplett lokale Speicherung auf deinem Gerät.',
                      ),
                      _InfoFeature(
                        icon: Icons.import_export_rounded,
                        text:
                            'Offline Import/Export: Sichere deine Daten jederzeit als CSV oder exportiere Belege offline.',
                      ),
                      _InfoFeature(
                        icon: Icons.cloud_outlined,
                        text:
                            'Cloud-Backup (Optional): Die verschlüsselte Google-Drive-Sicherung ist in Vorbereitung.',
                      ),
                      _InfoFeature(
                        icon: Icons.share_outlined,
                        text:
                            'Belege teilen: Sende Garantiedaten und Kassenbon-Fotos direkt per WhatsApp, Mail & Co. an Partner oder den Support.',
                      ),
                      _InfoFeature(
                        icon: Icons.policy_outlined,
                        text:
                            'Versicherungs-Schutz: Erstelle in den Einstellungen jederzeit einen professionellen PDF-Versicherungs-Report deiner Garantien inklusive aller Belege und Seriennummern – ideal für Schadensfälle oder Hausratversicherungen.',
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: GarantieHeldApp.emerald,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Verstanden'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoFeature extends StatelessWidget {
  const _InfoFeature({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final separator = text.indexOf(':');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, color: GarantieHeldApp.emerald, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 13,
                  height: 1.42,
                ),
                children: [
                  if (separator >= 0)
                    TextSpan(
                      text: text.substring(0, separator + 1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  TextSpan(
                    text: separator >= 0 ? text.substring(separator + 1) : text,
                  ),
                ],
              ),
            ),
          ),
        ],
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
  int _receiptIndex = 0;
  int _receiptImageRevision = 0;

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
        content: const Text(
          'Diese Aktion kann nicht rückgängig gemacht werden.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF87171),
            ),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await DatabaseHelper.instance.deleteWarranty(widget.warranty.id);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop(WarrantyDetailResult(deletedWarrantyId: widget.warranty.id));
  }

  Future<void> _shareWarranty() async {
    await _shareWarrantyData(context, widget.warranty);
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showReceiptFullscreen([String? selectedPath]) async {
    final receiptPaths = widget.warranty.allReceiptPaths.take(3).toList();
    if (receiptPaths.isEmpty) return;
    final initialIndex = selectedPath == null
        ? _receiptIndex.clamp(0, receiptPaths.length - 1)
        : receiptPaths.indexOf(selectedPath).clamp(0, receiptPaths.length - 1);
    final imagePath = receiptPaths.isEmpty ? '' : receiptPaths[initialIndex];
    if (_isPdfPath(imagePath)) {
      await OpenFilex.open(imagePath);
      return;
    }
    final rotatedPaths = await showDialog<List<String>>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => _ReceiptCarouselDialog(
        receiptPaths: receiptPaths,
        initialPage: initialIndex,
      ),
    );
    if (!mounted) return;
    await _evictReceiptImageCache(rotatedPaths ?? receiptPaths);
    if (mounted) setState(() => _receiptImageRevision++);
  }

  @override
  Widget build(BuildContext context) {
    final warranty = widget.warranty;
    final receiptPaths = warranty.allReceiptPaths.take(3).toList();
    final receiptPath = receiptPaths.isEmpty
        ? ''
        : receiptPaths[_receiptIndex.clamp(0, receiptPaths.length - 1)];
    final date = DateFormat(
      'dd.MM.yyyy',
      'de_DE',
    ).format(warranty.purchaseDate);
    final price = NumberFormat.currency(
      locale: 'de_DE',
      symbol: '€',
    ).format(warranty.price);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          warranty.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        actions: [
          IconButton(
            tooltip: 'Beleg teilen',
            onPressed: _shareWarranty,
            icon: const Icon(Icons.ios_share),
            color: const Color(0xFF10B981),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          if (receiptPath.isNotEmpty) ...[
            Stack(
              children: [
                GestureDetector(
                  onTap: _showReceiptFullscreen,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: _isPdfPath(receiptPath)
                        ? Container(
                            height: 180,
                            width: double.infinity,
                            color: GarantieHeldApp.surface,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.picture_as_pdf_rounded,
                                  color: Color(0xFFF87171),
                                  size: 54,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'PDF-Beleg öffnen',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          )
                        : Image.file(
                            File(receiptPath),
                            key: ValueKey(
                              '${receiptPath}_$_receiptImageRevision',
                            ),
                            height: 240,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(
                              height: 120,
                              child: Center(
                                child: Text('Belegfoto nicht verfügbar'),
                              ),
                            ),
                          ),
                  ),
                ),
                if (!_isPdfPath(receiptPath))
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
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          _isPdfPath(receiptPath)
                              ? 'Tippen zum Öffnen'
                              : 'Tippen zum Vergrößern',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (receiptPaths.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 62,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: receiptPaths.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => GestureDetector(
                    onTap: () => setState(() => _receiptIndex = index),
                    child: Container(
                      width: 62,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: index == _receiptIndex
                              ? GarantieHeldApp.emerald
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _isPdfPath(receiptPaths[index])
                          ? const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: Color(0xFFF87171),
                            )
                          : Image.file(
                              File(receiptPaths[index]),
                              key: ValueKey(
                                '${receiptPaths[index]}_$_receiptImageRevision',
                              ),
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  warranty.title,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _WarrantyStatusBadge(isActive: !warranty.isExpired),
            ],
          ),
          const SizedBox(height: 18),
          _WarrantyDetailTile(
            label: 'Händler',
            value: warranty.storeName.isEmpty ? '—' : warranty.storeName,
          ),
          _WarrantyDetailTile(label: 'Kaufpreis', value: price),
          _WarrantyDetailTile(label: 'Kaufdatum', value: date),
          _WarrantyDetailTile(
            label: 'Kategorie',
            value: _categoryLabel(warranty.category),
          ),
          _WarrantyDetailTile(
            label: 'Garantielaufzeit',
            value: warranty.durationLabel,
          ),
          _WarrantyDetailTile(
            label: 'Garantieende',
            value: DateFormat(
              'dd.MM.yyyy',
              'de_DE',
            ).format(warranty.expirationDate),
          ),
          if (warranty.serialNumber?.trim().isNotEmpty == true)
            _WarrantyDetailTile(
              label: 'Seriennummer / SN',
              value: warranty.serialNumber!.trim(),
            ),
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
        color: GarantieHeldApp.surfaceFor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
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
                    BoxShadow(
                      color: color.withValues(alpha: 0.75),
                      blurRadius: 6,
                    ),
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

bool _isPdfPath(String filePath) =>
    path.extension(filePath).toLowerCase() == '.pdf';

img.Image _resizeReceiptImage(img.Image image) {
  const maxEdge = 1920;
  if (image.width <= maxEdge && image.height <= maxEdge) return image;
  return image.width >= image.height
      ? img.copyResize(image, width: maxEdge)
      : img.copyResize(image, height: maxEdge);
}

Uint8List _compressReceiptImage(Uint8List sourceBytes) {
  final sourceImage = img.decodeImage(sourceBytes);
  if (sourceImage == null) {
    throw const FormatException('Das Belegfoto konnte nicht gelesen werden.');
  }
  final uprightImage = img.bakeOrientation(sourceImage);
  return img.encodeJpg(_resizeReceiptImage(uprightImage), quality: 82);
}

Future<String> _persistCompressedReceiptImage(String sourcePath) async {
  final sourceBytes = await File(sourcePath).readAsBytes();
  final jpegBytes = await compute(_compressReceiptImage, sourceBytes);
  final documents = await getApplicationDocumentsDirectory();
  final receiptsDirectory = Directory(path.join(documents.path, 'receipts'));
  await receiptsDirectory.create(recursive: true);
  final destination = path.join(
    receiptsDirectory.path,
    'receipt_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  return (await File(destination).writeAsBytes(jpegBytes, flush: true)).path;
}

Future<void> _evictReceiptImageCache(Iterable<String> filePaths) async {
  for (final filePath in filePaths) {
    if (filePath.isEmpty || _isPdfPath(filePath)) continue;
    await FileImage(File(filePath)).evict();
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
              _CountBadge(
                icon: Icons.shield_rounded,
                label: '$activeCount aktiv',
              ),
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
    required this.onShare,
    required this.onDetails,
    required this.onPreview,
    required this.onEdit,
    required this.onDelete,
  });

  final Warranty warranty;
  final String price;
  final String purchaseDate;
  final VoidCallback onShare;
  final VoidCallback onDetails;
  final VoidCallback onPreview;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  static const _icons = <Category, IconData>{
    Category.elektronik: Icons.devices,
    Category.haushalt: Icons.kitchen_rounded,
    Category.moebel: Icons.home_max_rounded,
    Category.werkzeug: Icons.handyman_rounded,
    Category.kleidung: Icons.checkroom_rounded,
    Category.sonstiges: Icons.inventory_2_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final expired = warranty.isExpired;
    final remainingDays = warranty.remainingDays;
    final nearingExpiry = !expired && remainingDays < 30;
    final criticalExpiry = remainingDays < 7;
    final statusColor = criticalExpiry
        ? Colors.redAccent
        : nearingExpiry
        ? const Color(0xFFF97316)
        : GarantieHeldApp.emerald;
    final status = expired
        ? 'Abgelaufen'
        : remainingDays == 0
        ? 'Achtung: Noch heute'
        : nearingExpiry
        ? 'Achtung: Noch $remainingDays Tage'
        : 'Noch $remainingDays Tage';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: GarantieHeldApp.surfaceFor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: GarantieHeldApp.surfaceFor(context),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: GarantieHeldApp.emerald.withValues(alpha: 0.16),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              _icons[warranty.category] ?? Icons.inventory_2_rounded,
              color: GarantieHeldApp.emerald,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  warranty.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${warranty.storeName.isEmpty ? 'Händler unbekannt' : warranty.storeName} · $purchaseDate',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.58),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Text(
                      price,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: criticalExpiry
                              ? Colors.red.withValues(alpha: 0.2)
                              : statusColor.withValues(alpha: 0.12),
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
          const SizedBox(width: 7),
          InkWell(
            onTap: onPreview,
            borderRadius: BorderRadius.circular(10),
            child: _receiptThumbnail(context),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _CardQuickAction(
                        tooltip: 'Teilen',
                        icon: Icons.share_outlined,
                        onTap: onShare,
                      ),
                      _CardQuickAction(
                        tooltip: 'Details',
                        icon: Icons.visibility_outlined,
                        onTap: onDetails,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _CardQuickAction(
                        tooltip: 'Bearbeiten',
                        icon: Icons.edit_outlined,
                        onTap: onEdit,
                      ),
                      _CardQuickAction(
                        tooltip: 'Löschen',
                        icon: Icons.delete_outline_rounded,
                        color: const Color(0xFFF87171),
                        onTap: onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptThumbnail(BuildContext context) {
    final filePath = warranty.imagePath;
    final isPdf = filePath.toLowerCase().endsWith('.pdf');
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: filePath.isEmpty
            ? ColoredBox(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF1F5F9),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: Colors.white54,
                  size: 24,
                ),
              )
            : isPdf
            ? ColoredBox(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF1F5F9),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Color(0xFFF87171),
                      size: 25,
                    ),
                    Text(
                      'PDF',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              )
            : Image.file(
                File(filePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF1F5F9),
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 22,
                  ),
                ),
              ),
      ),
    );
  }
}

class _CardQuickAction extends StatelessWidget {
  const _CardQuickAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.color = GarantieHeldApp.emerald,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(icon, color: color, size: 17),
          ),
        ),
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
        color: GarantieHeldApp.surfaceFor(context),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 42,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.55),
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
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.58),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: GarantieHeldApp.surfaceFor(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        children: [
          Icon(Icons.search_off_rounded, size: 34, color: Color(0xFF94A3B8)),
          SizedBox(height: 10),
          Text('Keine passende Garantie gefunden.'),
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
            const Icon(
              Icons.storage_rounded,
              size: 42,
              color: Color(0xFFF87171),
            ),
            const SizedBox(height: 12),
            const Text('Die Garantien konnten nicht geladen werden.'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Erneut versuchen'),
            ),
          ],
        ),
      ),
    );
  }
}

class WarrantyFormPage extends StatefulWidget {
  const WarrantyFormPage({super.key, required this.scanResult, this.warranty});

  final ReceiptOcrResult scanResult;
  final Warranty? warranty;

  @override
  State<WarrantyFormPage> createState() => _WarrantyFormPageState();
}

enum _ReceiptUploadSource { camera, gallery, pdf }

class _WarrantyFormPageState extends State<WarrantyFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  late final TextEditingController _titleController;
  final _storeController = TextEditingController();
  final _priceController = TextEditingController();
  final _serialNumberController = TextEditingController();
  final _purchaseDateController = TextEditingController();
  late ReceiptOcrResult _scanResult;
  final List<String> _receiptPaths = [];
  String? _activeReceiptPreviewPath;
  int _receiptPreviewRevision = 0;
  int _warrantyMonths = 24;
  int? _warrantyDays;
  int _reminderDaysBefore = 30;
  Category _category = Category.elektronik;
  DateTime? _purchaseDate;
  bool _dateError = false;
  bool _isAnalyzing = false;
  bool _analysisRequestInProgress = false;
  bool _allowPop = false;
  int _analysisGeneration = 0;
  String? _analysisError;
  String _analysisStatusText = 'Lade Beleg hoch & analysiere...';
  int _analysisStep = 1;
  bool _analysisSucceeded = false;

  @override
  void initState() {
    super.initState();
    final result = widget.scanResult;
    final existing = widget.warranty;
    _scanResult = result;
    _receiptPaths.addAll(
      existing?.allReceiptPaths ??
          (result.imagePath.isEmpty ? const [] : [result.imagePath]),
    );
    _activeReceiptPreviewPath = _receiptPaths.isEmpty
        ? result.imagePath
        : _receiptPaths.first;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _storeController.text = existing?.storeName ?? result.storeName;
    _serialNumberController.text = existing?.serialNumber ?? '';
    final initialPrice = existing?.price ?? result.productPrice;
    _priceController.text = initialPrice == null
        ? ''
        : initialPrice.toStringAsFixed(2).replaceAll('.', ',');
    _purchaseDate =
        existing?.purchaseDate ?? result.purchaseDate ?? DateTime.now();
    _category = existing?.category ?? _categoryFromGemini(result.category);
    _warrantyMonths = existing?.warrantyMonths ?? 24;
    _warrantyDays = existing?.warrantyDays;
    _reminderDaysBefore = existing?.reminderDaysBefore ?? 30;
    _purchaseDateController.text = DateFormat(
      'dd.MM.yyyy',
    ).format(_purchaseDate!);
    _isAnalyzing = existing == null && result.imagePath.isNotEmpty;
    if (_isAnalyzing) unawaited(_analyzeReceipt());
  }

  Future<void> _analyzeReceipt() async {
    if (_analysisRequestInProgress) return;
    _analysisRequestInProgress = true;
    final generation = ++_analysisGeneration;
    final imagePath = _scanResult.imagePath;
    final overlayDuration = Stopwatch()..start();
    try {
      if (kDebugMode) {
        debugPrint(
          '[Gemini] wizard analysis started | model=$geminiModelName | '
          'apiKeyConfigured=${GeminiReceiptAnalyzer.hasApiKey}',
        );
      }
      final result = await GeminiReceiptAnalyzer.analyzeReceiptWithFallback(
        imagePath: imagePath,
        onStepUpdate: (step) {
          if (!mounted || generation != _analysisGeneration) return;
          setState(() => _analysisStep = step);
        },
        onStatusUpdate: (status) {
          if (!mounted || generation != _analysisGeneration) return;
          setState(() {
            _analysisStatusText = status;
            _analysisSucceeded = status == 'Beleg erfolgreich analysiert! ✓';
          });
        },
      );
      if (result.productTitle.trim().isEmpty &&
          result.storeName.trim().isEmpty &&
          result.productPrice == null &&
          result.purchaseDate == null) {
        throw const FormatException('Gemini hat keine Bon-Daten erkannt.');
      }
      if (!mounted || generation != _analysisGeneration) return;
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (!mounted || generation != _analysisGeneration) return;
      setState(() {
        _scanResult = result.copyWith(imagePath: _scanResult.imagePath);
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
      if (!mounted || generation != _analysisGeneration) return;
      await _waitForMinimumAnalysisDuration(overlayDuration);
      if (!mounted || generation != _analysisGeneration) return;
      final failureMessage = error is GeminiModelCascadeException
          ? 'KI-Analyse nicht verfügbar. Bitte Daten manuell eintragen.'
          : 'Text konnte nicht automatisch erkannt werden, bitte Daten manuell prüfen.';
      setState(() {
        _isAnalyzing = false;
        _analysisError = failureMessage;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    } finally {
      if (generation == _analysisGeneration) {
        _analysisRequestInProgress = false;
      } else if (mounted && _isAnalyzing) {
        _analysisRequestInProgress = false;
        unawaited(_analyzeReceipt());
      }
    }
  }

  Future<void> _waitForMinimumAnalysisDuration(Stopwatch stopwatch) async {
    const minimumDuration = Duration(seconds: 3);
    final remaining = minimumDuration - stopwatch.elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
  }

  Future<void> _returnToScanner() async {
    final result = await Navigator.of(context).push<ReceiptOcrResult>(
      MaterialPageRoute(
        builder: (_) => ReceiptScannerScreen(
          onCancelToHome: () {
            if (mounted) setState(() => _allowPop = true);
          },
        ),
      ),
    );
    if (!mounted || result == null || result.imagePath.isEmpty) return;

    _analysisGeneration++;
    setState(() {
      _scanResult = result;
      _activeReceiptPreviewPath = result.imagePath;
      _receiptPreviewRevision++;
      _analysisStatusText = 'Lade Beleg hoch & analysiere...';
      _analysisStep = 1;
      _analysisSucceeded = false;
      _isAnalyzing = true;
      _analysisError = null;
    });
    unawaited(_analyzeReceipt());
  }

  void _handleBackNavigation() {
    if (widget.warranty != null) {
      Navigator.of(context).pop();
    } else {
      unawaited(_returnToScanner());
    }
  }

  Category _categoryFromGemini(String value) =>
      switch (value.trim().toLowerCase()) {
        'elektronik' => Category.elektronik,
        'haushalt' => Category.haushalt,
        'möbel' || 'moebel' => Category.moebel,
        'werkzeug' => Category.werkzeug,
        'kleidung' => Category.kleidung,
        _ => Category.sonstiges,
      };

  bool _durationMatches(_WarrantyDurationChoice choice) =>
      _warrantyMonths == choice.months && _warrantyDays == choice.days;

  void _selectDuration(_WarrantyDurationChoice choice) {
    _warrantyMonths = choice.months;
    _warrantyDays = choice.days;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _storeController.dispose();
    _priceController.dispose();
    _serialNumberController.dispose();
    _purchaseDateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_purchaseDate == null) {
      setState(() => _dateError = true);
      return;
    }
    final warranty = Warranty(
      id:
          widget.warranty?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      title: _titleController.text.trim(),
      storeName: _storeController.text.trim(),
      price: double.parse(_priceController.text.trim().replaceAll(',', '.')),
      purchaseDate: _purchaseDate!,
      warrantyMonths: _warrantyMonths,
      warrantyDays: _warrantyDays,
      category: _category,
      imagePath: _receiptPaths.isNotEmpty ? _receiptPaths.first : '',
      receiptPaths: List<String>.unmodifiable(_receiptPaths.take(3)),
      serialNumber: _serialNumberController.text.trim().isEmpty
          ? null
          : _serialNumberController.text.trim(),
      notes: widget.warranty?.notes,
      reminderDaysBefore: _reminderDaysBefore,
    );
    if (widget.warranty == null) {
      setState(() => _allowPop = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
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

  Future<void> _showReceiptPreview([String? selectedPath]) async {
    final paths = _receiptPaths.isNotEmpty
        ? List<String>.of(_receiptPaths)
        : (_scanResult.imagePath.isEmpty
              ? <String>[]
              : [_scanResult.imagePath]);
    if (paths.isEmpty) return;
    final initialPage = selectedPath == null
        ? 0
        : paths.indexOf(selectedPath).clamp(0, paths.length - 1);
    final rotatedPaths = await showDialog<List<String>>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) =>
          _ReceiptCarouselDialog(receiptPaths: paths, initialPage: initialPage),
    );
    if (!mounted) return;
    await _evictReceiptImageCache(rotatedPaths ?? paths);
    if (!mounted) return;
    setState(() {
      if (rotatedPaths?.isNotEmpty ?? false) {
        _activeReceiptPreviewPath = rotatedPaths!.last;
      }
      _receiptPreviewRevision++;
    });
  }

  Future<void> _chooseReceiptImage() async {
    if (_receiptPaths.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Maximal drei Belege pro Garantie.')),
      );
      return;
    }
    final source = await showModalBottomSheet<_ReceiptUploadSource>(
      context: context,
      useSafeArea: true,
      backgroundColor: GarantieHeldApp.surfaceFor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.only(
            bottom: 24,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Belegfoto hinzufügen',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: GarantieHeldApp.emerald,
                ),
                title: const Text('Foto jetzt aufnehmen'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ReceiptUploadSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: GarantieHeldApp.emerald,
                ),
                title: const Text('Aus Galerie auswählen'),
                onTap: () => Navigator.of(
                  sheetContext,
                ).pop(_ReceiptUploadSource.gallery),
              ),
              ListTile(
                leading: const Icon(
                  Icons.picture_as_pdf_rounded,
                  color: GarantieHeldApp.emerald,
                ),
                title: const Text('PDF auswählen'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_ReceiptUploadSource.pdf),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      if (source == _ReceiptUploadSource.pdf) {
        final selection = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf'],
          withData: true,
        );
        if (selection == null || selection.files.isEmpty || !mounted) return;
        final savedPath = await _persistSelectedReceiptFile(
          selection.files.single,
        );
        if (!mounted) return;
        _analysisGeneration++;
        _analysisRequestInProgress = false;
        setState(() {
          if (_receiptPaths.length >= 3) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Maximal drei Belege pro Garantie.'),
              ),
            );
            return;
          }
          _receiptPaths.add(savedPath);
          if (_activeReceiptPreviewPath?.isEmpty ?? true) {
            _activeReceiptPreviewPath = _receiptPaths.first;
          }
          _scanResult = _scanResult.copyWith(imagePath: _receiptPaths.first);
          _isAnalyzing = false;
          _analysisError = null;
        });
        return;
      }
      final image = await _imagePicker.pickImage(
        source: source == _ReceiptUploadSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 92,
      );
      if (image == null || !mounted) return;
      final savedPath = await _persistSelectedReceiptImage(image.path);
      if (!mounted) return;
      setState(() {
        if (_receiptPaths.length >= 3) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximal drei Belege pro Garantie.')),
          );
          return;
        }
        _receiptPaths.add(savedPath);
        if (_activeReceiptPreviewPath?.isEmpty ?? true) {
          _activeReceiptPreviewPath = _receiptPaths.first;
        }
        _scanResult = _scanResult.copyWith(imagePath: _receiptPaths.first);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Das Belegfoto konnte nicht geladen werden.'),
        ),
      );
    }
  }

  Future<String> _persistSelectedReceiptImage(String sourcePath) async {
    return _persistCompressedReceiptImage(sourcePath);
  }

  Future<String> _persistSelectedReceiptFile(PlatformFile selectedFile) async {
    final documents = await getApplicationDocumentsDirectory();
    final receiptsDirectory = Directory(path.join(documents.path, 'receipts'));
    await receiptsDirectory.create(recursive: true);
    final destination = path.join(
      receiptsDirectory.path,
      'receipt_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    final sourcePath = selectedFile.path;
    if (sourcePath != null) {
      return (await File(sourcePath).copy(destination)).path;
    }
    final bytes = selectedFile.bytes;
    if (bytes == null)
      throw const FormatException('PDF-Datei ist nicht lesbar.');
    return (await File(destination).writeAsBytes(bytes, flush: true)).path;
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
    const durationChoices = [
      _WarrantyDurationChoice(label: '2 Wochen', months: 0, days: 14),
      _WarrantyDurationChoice(label: '1 Monat', months: 1),
      _WarrantyDurationChoice(label: '2 Monate', months: 2),
      _WarrantyDurationChoice(label: '12 Monate', months: 12),
      _WarrantyDurationChoice(label: '24 Monate', months: 24),
      _WarrantyDurationChoice(label: '36 Monate', months: 36),
      _WarrantyDurationChoice(label: '48 Monate', months: 48),
      _WarrantyDurationChoice(label: '60 Monate', months: 60),
    ];
    final isEditing = widget.warranty != null;
    final previewPath = _activeReceiptPreviewPath ?? _scanResult.imagePath;
    return Stack(
      fit: StackFit.expand,
      children: [
        PopScope<Warranty?>(
          canPop: isEditing || _allowPop,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && !isEditing && !_allowPop) {
              _handleBackNavigation();
            }
          },
          child: Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: AppBar(
              backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
              leading: IconButton(
                tooltip: 'Zurück',
                onPressed: _handleBackNavigation,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              title: Text(
                isEditing ? 'Garantie bearbeiten' : 'Garantie bestätigen',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              actions: [
                if (!isEditing)
                  Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Center(
                      child: Text(
                        'Schritt 2/2',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.56),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFF263449),
                ),
              ),
            ),
            body: Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
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
                                  color: GarantieHeldApp.surfaceFor(context),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.receipt_long_rounded,
                                  color: GarantieHeldApp.emerald,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
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
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
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
                          if (previewPath.isNotEmpty)
                            Stack(
                              children: [
                                GestureDetector(
                                  onTap: () => _showReceiptPreview(previewPath),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: _isPdfPath(previewPath)
                                        ? Container(
                                            height: 180,
                                            width: double.infinity,
                                            color: GarantieHeldApp.surface,
                                            child: const Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.picture_as_pdf_rounded,
                                                  color: Color(0xFFF87171),
                                                  size: 48,
                                                ),
                                                SizedBox(height: 8),
                                                Text(
                                                  'PDF-Beleg öffnen',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        : Image.file(
                                            File(previewPath),
                                            key: ValueKey(
                                              '${previewPath}_$_receiptPreviewRevision',
                                            ),
                                            height: 180,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Container(
                                              height: 180,
                                              width: double.infinity,
                                              alignment: Alignment.center,
                                              color: GarantieHeldApp.surfaceFor(
                                                context,
                                              ),
                                              child: const Text(
                                                'Kassenbon-Bild nicht verfügbar',
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: Material(
                                    color: const Color(0xB31E293B),
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      tooltip: 'Belegdatei hinzufügen',
                                      onPressed: _receiptPaths.length >= 3
                                          ? null
                                          : _chooseReceiptImage,
                                      icon: const Icon(Icons.add_rounded),
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            GestureDetector(
                              onTap: _chooseReceiptImage,
                              child: CustomPaint(
                                foregroundPainter:
                                    _DashedReceiptBorderPainter(),
                                child: Container(
                                  width: double.infinity,
                                  height: 180,
                                  decoration: BoxDecoration(
                                    color: GarantieHeldApp.surfaceFor(context),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_a_photo_rounded,
                                        color: GarantieHeldApp.emerald,
                                        size: 34,
                                      ),
                                      SizedBox(height: 12),
                                      Text(
                                        'Belegfoto hinzufügen (optional)',
                                        style: TextStyle(
                                          color: Color(0xFFD6E0ED),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          if (_receiptPaths.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 66,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _receiptPaths.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final receiptPath = _receiptPaths[index];
                                  return Stack(
                                    children: [
                                      GestureDetector(
                                        onTap: () =>
                                            _showReceiptPreview(receiptPath),
                                        child: Container(
                                          width: 62,
                                          height: 62,
                                          decoration: BoxDecoration(
                                            color: GarantieHeldApp.surfaceFor(
                                              context,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: _isPdfPath(receiptPath)
                                              ? const Icon(
                                                  Icons.picture_as_pdf_rounded,
                                                  color: Color(0xFFF87171),
                                                  size: 30,
                                                )
                                              : Image.file(
                                                  File(receiptPath),
                                                  key: ValueKey(
                                                    '${receiptPath}_$_receiptPreviewRevision',
                                                  ),
                                                  fit: BoxFit.cover,
                                                ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        child: InkWell(
                                          onTap: () => setState(() {
                                            _receiptPaths.removeAt(index);
                                            if (_activeReceiptPreviewPath ==
                                                receiptPath) {
                                              _activeReceiptPreviewPath =
                                                  _receiptPaths.isEmpty
                                                  ? ''
                                                  : _receiptPaths.first;
                                            }
                                            _receiptPreviewRevision++;
                                            _scanResult = _scanResult.copyWith(
                                              imagePath: _receiptPaths.isEmpty
                                                  ? ''
                                                  : _receiptPaths.first,
                                            );
                                          }),
                                          child: const Icon(
                                            Icons.cancel,
                                            size: 18,
                                            color: Color(0xFFF87171),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                          if (previewPath.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                _isPdfPath(previewPath)
                                    ? 'Tippen zum Öffnen'
                                    : 'Tippen zum Vergrößern',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.52),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          if (_analysisError != null) ...[
                            _GeminiAnalysisErrorCard(message: _analysisError!),
                            const SizedBox(height: 16),
                          ],
                          const _WizardFieldLabel('Produktname'),
                          TextFormField(
                            controller: _titleController,
                            autofocus:
                                !_isAnalyzing && _titleController.text.isEmpty,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: _wizardInputDecoration(
                              hintText: 'z. B. MOBILE ENERGIESTATION',
                              suffixIcon: _clearButton(_titleController),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
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
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: _wizardInputDecoration(
                                      hintText: 'Händlername',
                                      suffixIcon: _clearButton(
                                        _storeController,
                                      ),
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
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: _wizardInputDecoration(
                                      hintText: '0,00',
                                      suffixIcon: _clearButton(
                                        _priceController,
                                      ),
                                    ),
                                    validator: (value) {
                                      final parsed = double.tryParse(
                                        (value ?? '').trim().replaceAll(
                                          ',',
                                          '.',
                                        ),
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
                          const _WizardFieldLabel(
                            'Seriennummer / SN (optional)',
                          ),
                          TextFormField(
                            controller: _serialNumberController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _wizardInputDecoration(
                              hintText: 'z. B. SN123456789',
                              suffixIcon: _clearButton(_serialNumberController),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const _WizardFieldLabel('Kaufdatum'),
                          TextFormField(
                            controller: _purchaseDateController,
                            readOnly: true,
                            onTap: _selectPurchaseDate,
                            decoration: _wizardInputDecoration(
                              hintText: 'Datum auswählen',
                              errorText: _dateError
                                  ? 'Bitte Kaufdatum auswählen'
                                  : null,
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
                                for (final choice in durationChoices.take(
                                  6,
                                )) ...[
                                  _WarrantyDurationPill(
                                    label: choice.label,
                                    selected: _durationMatches(choice),
                                    onTap: () =>
                                        setState(() => _selectDuration(choice)),
                                  ),
                                  if (choice != durationChoices.take(6).last)
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
                                .map(
                                  (category) => DropdownMenuItem(
                                    value: category,
                                    child: Text(_categoryLabel(category)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) =>
                                setState(() => _category = value ?? _category),
                          ),
                          const SizedBox(height: 16),
                          const _WizardFieldLabel('Weitere Laufzeit'),
                          DropdownButtonFormField<_WarrantyDurationChoice>(
                            value: durationChoices.firstWhere(_durationMatches),
                            decoration: _wizardInputDecoration(
                              hintText: 'Laufzeit auswählen',
                            ),
                            items: durationChoices
                                .map(
                                  (choice) => DropdownMenuItem(
                                    value: choice,
                                    child: Text(choice.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null)
                                setState(() => _selectDuration(value));
                            },
                          ),
                          const SizedBox(height: 16),
                          const _WizardFieldLabel('Erinnerung planen'),
                          DropdownButtonFormField<int>(
                            value: _reminderDaysBefore,
                            decoration: _wizardInputDecoration(
                              hintText: 'Erinnerung auswählen',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 0,
                                child: Text('Am Tag des Ablaufs'),
                              ),
                              DropdownMenuItem(
                                value: 7,
                                child: Text('1 Woche vorher'),
                              ),
                              DropdownMenuItem(
                                value: 14,
                                child: Text('2 Wochen vorher'),
                              ),
                              DropdownMenuItem(
                                value: 30,
                                child: Text('1 Monat vorher'),
                              ),
                              DropdownMenuItem(
                                value: -1,
                                child: Text('Keine Erinnerung'),
                              ),
                            ],
                            onChanged: (value) => setState(
                              () => _reminderDaysBefore =
                                  value ?? _reminderDaysBefore,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    bottom: true,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        bottom: 16,
                        left: 16,
                        right: 16,
                      ),
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
          ),
        ),
        Positioned.fill(
          child: AbsorbPointer(
            absorbing: _isAnalyzing,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: _isAnalyzing
                  ? _ReceiptAnalysisOverlay(
                      key: ValueKey('receipt-analysis-overlay'),
                      statusText: _analysisStatusText,
                      step: _analysisStep,
                      isSuccess: _analysisSucceeded,
                    )
                  : const SizedBox.expand(
                      key: ValueKey('receipt-analysis-idle'),
                    ),
            ),
          ),
        ),
      ],
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
    fillColor: GarantieHeldApp.surfaceFor(context),
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

class _ReceiptAnalysisOverlay extends StatelessWidget {
  const _ReceiptAnalysisOverlay({
    required this.statusText,
    required this.step,
    required this.isSuccess,
    super.key,
  });

  final String statusText;
  final int step;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: const ColoredBox(color: Colors.black54),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xED111827),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: isSuccess
                          ? const Icon(
                              Icons.check_circle_rounded,
                              key: ValueKey('receipt-analysis-success'),
                              color: GarantieHeldApp.emerald,
                              size: 48,
                            )
                          : const SizedBox(
                              key: ValueKey('receipt-analysis-progress'),
                              width: 48,
                              height: 48,
                              child: CircularProgressIndicator(
                                color: GarantieHeldApp.emerald,
                                strokeWidth: 4,
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'KI-Erfassung läuft...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Text(
                        statusText,
                        key: ValueKey(statusText),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '(Versuch $step von 4)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _GeminiAnalysisErrorCard extends StatelessWidget {
  const _GeminiAnalysisErrorCard({required this.message});

  final String message;

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
                  message,
                  style: const TextStyle(color: Color(0xFFFECACA)),
                ),
              ),
            ],
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
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.84),
        ),
      ),
    );
  }
}

class _WarrantyDurationChoice {
  const _WarrantyDurationChoice({
    required this.label,
    required this.months,
    this.days,
  });

  final String label;
  final int months;
  final int? days;
}

class _WarrantyDurationPill extends StatelessWidget {
  const _WarrantyDurationPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$label Garantie',
      child: Material(
        color: selected
            ? GarantieHeldApp.emerald
            : GarantieHeldApp.surfaceFor(context),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.82),
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
  const ReceiptScannerScreen({super.key, this.onCancelToHome});

  final VoidCallback? onCancelToHome;

  @override
  State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State<ReceiptScannerScreen> {
  CameraController? _controller;
  final ImagePicker _imagePicker = ImagePicker();
  String? _error;
  bool _busy = false;
  FlashMode _flashMode = FlashMode.off;
  bool _canOpenSettings = false;
  bool _allowPop = false;
  bool _leavingHome = false;

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
            _canOpenSettings =
                permission.isPermanentlyDenied || permission.isRestricted;
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
      try {
        await controller.setFlashMode(FlashMode.off);
      } on CameraException {
        // Some camera devices do not expose flash control.
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException catch (error) {
      if (mounted) setState(() => _error = error.description ?? error.code);
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Die Kamera konnte nicht gestartet werden.');
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
      final imagePath = await _persistReceiptImage(image.path);

      if (identical(_controller, controller)) _controller = null;
      await controller.dispose();
      if (mounted) {
        await _popWithResult(ReceiptOcrParser.parse('', imagePath: imagePath));
      }
    } on CameraException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.description ?? 'Foto konnte nicht aufgenommen werden.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Das Bonfoto konnte nicht verarbeitet werden.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    final nextMode = switch (_flashMode) {
      FlashMode.off => FlashMode.always,
      FlashMode.always || FlashMode.torch => FlashMode.auto,
      FlashMode.auto => FlashMode.off,
    };
    try {
      await controller.setFlashMode(nextMode);
      if (mounted) setState(() => _flashMode = nextMode);
    } on CameraException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.description ?? 'Blitz konnte nicht geändert werden.',
            ),
          ),
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

      final imagePath = await _persistReceiptImage(image.path);

      final controller = _controller;
      _controller = null;
      await controller?.dispose();
      if (mounted) {
        await _popWithResult(ReceiptOcrParser.parse('', imagePath: imagePath));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Das Foto konnte nicht aus der Galerie geladen werden.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continueManually() {
    if (_busy) return;
    unawaited(_popWithResult(ReceiptOcrParser.parse('')));
  }

  Future<void> _popWithResult(ReceiptOcrResult result) async {
    _allowPop = true;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  Future<void> _leaveToHome() async {
    if (_busy || _leavingHome) return;
    _leavingHome = true;
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
    if (!mounted) return;

    widget.onCancelToHome?.call();
    _allowPop = true;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<String> _persistReceiptImage(String sourcePath) async {
    return _persistCompressedReceiptImage(sourcePath);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope<ReceiptOcrResult>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_allowPop) unawaited(_leaveToHome());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          titleSpacing: 0,
          title: const Text('Bon scannen'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: 'Zur Startseite',
            onPressed: _busy ? null : _leaveToHome,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          actions: [
            IconButton(
              tooltip: switch (_flashMode) {
                FlashMode.off => 'Blitz aus · antippen für An',
                FlashMode.always ||
                FlashMode.torch => 'Blitz an · antippen für Auto',
                FlashMode.auto => 'Blitz automatisch · antippen für Aus',
              },
              onPressed:
                  controller == null || !controller.value.isInitialized || _busy
                  ? null
                  : _toggleFlash,
              icon: Icon(switch (_flashMode) {
                FlashMode.off => Icons.flash_off,
                FlashMode.always || FlashMode.torch => Icons.flash_on,
                FlashMode.auto => Icons.flash_auto,
              }),
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
                      const Text(
                        'Du kannst die Garantie anschließend manuell erfassen.',
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: () => _continueManually(),
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
                child: CircularProgressIndicator(
                  color: GarantieHeldApp.emerald,
                ),
              )
            : _buildCameraScanner(controller),
      ),
    );
  }

  Widget _buildCameraScanner(CameraController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final guideWidth = constraints.maxWidth * 0.86;
        final guideHeight = constraints.maxHeight * 0.60;
        final guideRect = Rect.fromCenter(
          center: Offset(
            constraints.maxWidth / 2,
            constraints.maxHeight * 0.32,
          ),
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
            Positioned.fromRect(rect: guideRect, child: const _ScannerGuide()),
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
                      Semantics(
                        button: true,
                        label: 'Kassenbon fotografieren',
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _busy ? null : _captureAndRecognize,
                          child: Container(
                            width: 82,
                            height: 82,
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: DecoratedBox(
                              decoration: const BoxDecoration(
                                color: GarantieHeldApp.emerald,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: _busy
                                    ? const SizedBox.square(
                                        dimension: 30,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.camera_alt_rounded,
                                        size: 34,
                                        color: Colors.white,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _continueManually,
                        icon: const Icon(Icons.edit_note_rounded, size: 19),
                        label: const Text('Manuell eingeben  →'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0x991E293B),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 22,
                      ),
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
    return IgnorePointer(child: CustomPaint(painter: _ScannerCornersPainter()));
  }
}

class _DashedReceiptBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)));
    final paint = Paint()
      ..color = GarantieHeldApp.emerald.withValues(alpha: 0.72)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 8).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 6;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedReceiptBorderPainter oldDelegate) =>
      false;
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
      ..quadraticBezierTo(
        size.width - inset,
        inset,
        size.width - inset,
        inset + 20,
      )
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
      ..quadraticBezierTo(
        inset,
        size.height - inset,
        inset,
        size.height - inset - 20,
      )
      ..lineTo(inset, size.height - cornerLength);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScannerCornersPainter oldDelegate) => false;
}
