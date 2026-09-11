import 'package:flutter/material.dart';

/// Locks the app to a phone-sized viewport when running on a wide screen
/// (desktop Chrome). On a real phone / narrow window it renders full-bleed,
/// which is how the PWA will actually be used.
class MobileFrame extends StatelessWidget {
  const MobileFrame({super.key, required this.child});

  final Widget child;

  /// Pixel 9 logical size.
  static const _phone = Size(412, 915);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits = constraints.maxWidth <= _phone.width + 40;
        if (fits) return child;

        final scale = (constraints.maxHeight - 32) / _phone.height;
        final height = scale < 1 ? _phone.height * scale : _phone.height;
        final width = scale < 1 ? _phone.width * scale : _phone.width;

        return ColoredBox(
          color: const Color(0xFF2D3133),
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: SizedBox(
                width: width,
                height: height,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _phone.width,
                    height: _phone.height,
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        size: _phone,
                        padding: const EdgeInsets.only(top: 24, bottom: 12),
                        viewPadding: const EdgeInsets.only(top: 24, bottom: 12),
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
