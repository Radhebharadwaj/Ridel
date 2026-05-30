import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ridel/core/utils/ridel_bounce_button.dart';

const Color kRidelMatteDark = Color(0xFF0B0E17);

Future<String?> showSmartTicketingOverlay(BuildContext context, {bool isBus = false}) async {
  return await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss Smart Ticketing Overlay',
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      final isLightMode = Theme.of(context).brightness == Brightness.light;
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: SingleChildScrollView(
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: animation,
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                          // Card 1: Recharge Smart Card
                          if (!isBus) ...[
                            RidelBounceButton(
                              onTap: () => Navigator.of(context).pop('recharge'),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: _cardDecoration(isLightMode),
                              child: Row(
                                children: [
                                  Image.asset(
                                    'assets/images/metrocard.png',
                                    height: 40,
                                    width: 60,
                                    fit: BoxFit.contain,
                                    alignment: Alignment.centerLeft,
                                    errorBuilder: (c, e, s) =>
                                        Icon(Icons.broken_image, size: 40, color: isLightMode ? Colors.black54 : Colors.white54),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Recharge Smart Card',
                                            style: _titleStyle(isLightMode)),
                                        const SizedBox(height: 4),
                                        Text('Instant top-up for your metro card',
                                            style: _subtitleStyle(isLightMode)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          ],
                          // Card 2: Book via WhatsApp Bot
                          RidelBounceButton(
                            onTap: () => Navigator.of(context).pop('whatsapp'),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: _cardDecoration(isLightMode),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Image.asset(
                                        'assets/images/whatsapp.png',
                                        height: 48,
                                        width: 48,
                                        fit: BoxFit.contain,
                                        errorBuilder: (c, e, s) => Icon(
                                            Icons.broken_image,
                                            size: 48, color: isLightMode ? Colors.black54 : Colors.white54),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text('Book via WhatsApp Bot',
                                                style: _titleStyle(isLightMode)),
                                            const SizedBox(height: 4),
                                            Text('Fastest • Works with any UPI',
                                                style: _subtitleStyle(isLightMode)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 56.0),
                                    child: Wrap(
                                      spacing: 8.0,
                                      runSpacing: 8.0,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Image.asset(
                                          'assets/images/gpay.png',
                                          height: 24,
                                          fit: BoxFit.contain,
                                          errorBuilder: (c, e, s) => Icon(
                                              Icons.broken_image,
                                              size: 16, color: isLightMode ? Colors.black54 : Colors.white54),
                                        ),
                                        Image.asset(
                                          'assets/images/phonepe.png',
                                          height: 24,
                                          fit: BoxFit.contain,
                                          errorBuilder: (c, e, s) => Icon(
                                              Icons.broken_image,
                                              size: 16, color: isLightMode ? Colors.black54 : Colors.white54),
                                        ),
                                        Image.asset(
                                          'assets/images/paytm.png',
                                          height: 24,
                                          fit: BoxFit.contain,
                                          errorBuilder: (c, e, s) => Icon(
                                              Icons.broken_image,
                                              size: 16, color: isLightMode ? Colors.black54 : Colors.white54),
                                        ),
                                        Image.asset(
                                          'assets/images/upi.png',
                                          height: 20,
                                          fit: BoxFit.contain,
                                          errorBuilder: (c, e, s) => Icon(
                                              Icons.broken_image,
                                              size: 16, color: isLightMode ? Colors.black54 : Colors.white54),
                                        ),
                                        Text('+ many more',
                                            style: GoogleFonts.inter(
                                                color: isLightMode ? Colors.black54 : Colors.white54,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Bottom Row - Pixel Perfect Symmetry
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: RidelBounceButton(
                                    onTap: () =>
                                        Navigator.of(context).pop('paytm'),
                                    child: Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: _cardDecoration(isLightMode),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Image.asset(
                                            'assets/images/paytm.png',
                                            height: 36,
                                            fit: BoxFit.contain,
                                            errorBuilder: (context, error,
                                                    stackTrace) =>
                                                Text('Paytm',
                                                    style: GoogleFonts.inter(
                                                        color: Colors.blueAccent,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 24)),
                                          ),
                                          const Spacer(),
                                          Text('Book on Paytm',
                                              style: _titleStyle(isLightMode)),
                                          const SizedBox(height: 4),
                                          Text(isBus ? 'Direct bus ticketing mini-app.' : 'Direct metro ticketing mini-app.',
                                              style: _subtitleStyle(isLightMode)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: RidelBounceButton(
                                    onTap: () =>
                                        Navigator.of(context).pop('fare_calc'),
                                    child: Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: _cardDecoration(isLightMode),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildSimulatedCalculator(isLightMode),
                                          const Spacer(),
                                          Text('Fare Calculator',
                                              style: _titleStyle(isLightMode),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 4),
                                          Text(
                                              'Check ticket prices & route details.',
                                              style: _subtitleStyle(isLightMode)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

Widget buildSmallLogo(String url) {
  return Container(
    height: 24,
    width: 36,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(6),
    ),
    child: CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      errorWidget: (context, url, error) =>
          const Icon(Icons.payment, size: 12, color: Colors.white),
    ),
  );
}

BoxDecoration _cardDecoration(bool isLightMode) {
  return BoxDecoration(
    color: isLightMode ? Colors.white : const Color(0xFF1C1F26),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: isLightMode 
          ? Colors.black.withValues(alpha: 0.06) 
          : Colors.white.withValues(alpha: 0.08),
      width: 1,
    ),
    boxShadow: isLightMode ? [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 16,
        offset: const Offset(0, 4),
      )
    ] : [],
  );
}

TextStyle _titleStyle(bool isLightMode) => GoogleFonts.inter(
    color: isLightMode ? Colors.black87 : Colors.white, fontSize: 16, fontWeight: FontWeight.w600);
TextStyle _subtitleStyle(bool isLightMode) =>
    GoogleFonts.inter(color: isLightMode ? Colors.black54 : Colors.white54, fontSize: 12, height: 1.4);

Widget _buildSimulatedCalculator(bool isLightMode) {
  return Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: isLightMode ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: isLightMode ? Colors.black.withValues(alpha: 0.05) : Colors.white24),
    ),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Icon(Icons.currency_rupee_rounded,
            color: isLightMode ? Colors.cyan.shade600 : Colors.cyanAccent, size: 22),
        Positioned(
          top: 6,
          right: 6,
          child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                  color: isLightMode ? Colors.black54 : Colors.white70, shape: BoxShape.circle)),
        ),
        Positioned(
          bottom: 6,
          left: 8,
          child: Container(width: 14, height: 2, color: isLightMode ? Colors.black38 : Colors.white54),
        ),
      ],
    ),
  );
}
