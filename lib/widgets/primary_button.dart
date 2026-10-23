import 'package:flutter/material.dart';

enum PrimaryButtonTone { emerald, destructive }

/// Consistent primary CTA used by the dashboard, wizard, and detail screen.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tone = PrimaryButtonTone.emerald,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final PrimaryButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = tone == PrimaryButtonTone.destructive
        ? const Color(0xFFEF4444)
        : const Color(0xFF10B981);

    return SizedBox(
      height: 54,
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}


