import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Pocketknife brand mark — dark navy rounded tile with a stylised pocketknife blade
/// and royal blue pivot accent dot, matching the design in the reference images.
class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.28;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.18),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/images/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => CustomPaint(
            painter: _BladePainter(),
            size: Size(size, size),
          ),
        ),
      ),
    );
  }
}

class _BladePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final pivot = Offset(w * 0.32, h * 0.68);

    // Main blade leaf
    final blade = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..quadraticBezierTo(w * 0.40, h * 0.24, w * 0.76, h * 0.26)
      ..quadraticBezierTo(w * 0.62, h * 0.50, pivot.dx, pivot.dy)
      ..close();
    canvas.drawPath(blade, Paint()..color = Colors.white);

    // Accent spine along blade edge
    final spine = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.05
      ..strokeCap = StrokeCap.round;
    final spinePath = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..quadraticBezierTo(w * 0.40, h * 0.24, w * 0.76, h * 0.26);
    canvas.drawPath(spinePath, spine);

    // Blue pivot rivet dot
    canvas.drawCircle(pivot, w * 0.08, Paint()..color = AppColors.primary);
    canvas.drawCircle(pivot, w * 0.035, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
