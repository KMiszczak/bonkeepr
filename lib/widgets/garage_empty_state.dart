import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Theme-aware illustration and copy shown before the first warranty is added.
class GarageEmptyState extends StatelessWidget {
  const GarageEmptyState({super.key, required this.isRetroMode});

  final bool isRetroMode;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headingColor = isRetroMode
        ? const Color(0xFFFFD700)
        : isDark
        ? Colors.white
        : const Color(0xFF172033);
    final descriptionColor = isRetroMode
        ? const Color(0xFFE2E8F0)
        : isDark
        ? Colors.white70
        : const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            isRetroMode
                ? 'assets/EmptyState8Bit.png'
                : 'assets/EmptyStatePic.png',
            height: 180,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 12),
          Text(
            isRetroMode
                ? 'DEINE GARAGE IST NOCH LEER!'
                : 'Deine Garage ist noch leer!',
            textAlign: TextAlign.center,
            style: isRetroMode
                ? GoogleFonts.pressStart2p(
                    color: headingColor,
                    fontSize: 14,
                    height: 1.7,
                    shadows: const [
                      Shadow(color: Colors.black, offset: Offset(2, 2)),
                    ],
                  )
                : TextStyle(
                    color: headingColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            isRetroMode
                ? 'SCANNE DEINEN ERSTEN BELEG, UM DIE GARANTIE SICHER AUFZUBEWAHREN.'
                : 'Scanne deinen ersten Beleg, um die Garantie sicher aufzubewahren.',
            textAlign: TextAlign.center,
            style: isRetroMode
                ? GoogleFonts.vt323(
                    color: descriptionColor,
                    fontSize: 20,
                    height: 1.1,
                  )
                : TextStyle(color: descriptionColor, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }
}
