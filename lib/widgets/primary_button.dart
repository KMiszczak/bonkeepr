import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme_controller.dart';
import 'retro_icon.dart';

enum PrimaryButtonTone { emerald, destructive }

/// Consistent primary CTA used by the dashboard, wizard, and detail screen.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tone = PrimaryButtonTone.emerald,
    this.retroLeading,
    this.retroFontSize = 10,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final PrimaryButtonTone tone;
  final Widget? retroLeading;
  final double retroFontSize;

  @override
  Widget build(BuildContext context) {
    final isRetroMode = ThemeController.instance.isRetroMode;
    final backgroundColor = tone == PrimaryButtonTone.destructive
        ? const Color(0xFFE57373)
        : isRetroMode
        ? const Color(0xFF00FF66)
        : const Color(0xFF10B981);

    return Container(
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
      child: SizedBox(
        height: 54,
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: isRetroMode ? Colors.black : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: isRetroMode
                  ? BorderRadius.zero
                  : BorderRadius.circular(16),
              side: isRetroMode
                  ? const BorderSide(color: Colors.black, width: 3)
                  : BorderSide.none,
            ),
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRetroMode && retroLeading != null)
                retroLeading!
              else
                RetroIcon(icon, size: 20),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: isRetroMode
                    ? GoogleFonts.pressStart2p(
                        fontSize: retroFontSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      )
                    : const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
