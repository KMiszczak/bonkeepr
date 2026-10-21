import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'warranty_model.dart';
import 'database_helper.dart';

void main() => runApp(const GarantieHeldApp());

class GarantieHeldApp extends StatelessWidget {
  const GarantieHeldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GarantieHeld',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(primary: Color(0xFF10B981), surface: Color(0xFF1E293B)),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('GarantieHeld', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: FutureBuilder<List<Warranty>>(
        future: DatabaseHelper.instance.getAllWarranties(),
        builder: (context, snapshot) {
          final list = snapshot.data ?? [];
          return Center(
            child: Text(
              ' Garantien gespeichert',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        backgroundColor: const Color(0xFF10B981),
        label: const Text('Bon scannen'),
        icon: const Icon(Icons.camera_alt),
      ),
    );
  }
}
