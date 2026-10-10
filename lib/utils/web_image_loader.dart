import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';

/// Web-safe image loader that handles CORS issues
class WebImageLoader {
  static Color _defaultAvatarTextColor(Color backgroundColor) {
    final brightness = ThemeData.estimateBrightnessForColor(backgroundColor);
    return brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF5E35B1);
  }

  static String _sanitizeUrl(String rawUrl) {
    var value = rawUrl.trim();
    if (value.isEmpty) return value;

    // Keep base64 images unchanged.
    if (value.startsWith('data:image')) return value;

    // Remove wrapping quotes.
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1).trim();
    }

    // Drop newlines if any
    if (value.contains('\n') || value.contains('\r')) {
      value = value.split(RegExp(r'[\r\n]+')).first.trim();
    }

    // Safely encode spaces in URLs instead of cutting off the URL
    if (value.contains(' ')) {
      value = value.replaceAll(' ', '%20');
    }

    // Upgrade http to https for mixed-content web security
    if (value.startsWith('http://')) {
      value = 'https://${value.substring(7)}';
    }

    // Recover malformed values with trailing junk only from the last path segment (filename)
    final lastSlashIndex = value.lastIndexOf('/');
    if (lastSlashIndex != -1 && lastSlashIndex < value.length - 1) {
      final filename = value.substring(lastSlashIndex + 1);
      final extensionMatch = RegExp(
        r'\.(jpg|jpeg|png|webp|gif|bmp)',
        caseSensitive: false,
      ).firstMatch(filename);
      if (extensionMatch != null) {
        final extEnd = extensionMatch.end;
        if (extEnd < filename.length) {
          final nextChar = filename.substring(extEnd, extEnd + 1);
          if (nextChar != '?' && nextChar != '#' && nextChar != '&') {
            value = value.substring(0, lastSlashIndex + 1 + extEnd);
          }
        }
      }
    }

    return value;
  }

  static Widget _defaultPlaceholder({
    double? width,
    double? height,
    Widget? customWidget,
  }) {
    if (customWidget != null) return customWidget;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: Colors.grey.shade400,
          size: (width != null && height != null)
              ? (width < height ? width * 0.35 : height * 0.35).clamp(18.0, 36.0)
              : 28.0,
        ),
      ),
    );
  }

  static Uint8List? _decodeDataImage(String rawUrl) {
    final url = _sanitizeUrl(rawUrl);
    if (!url.startsWith('data:image')) return null;
    final commaIndex = url.indexOf(',');
    if (commaIndex <= 0 || commaIndex == url.length - 1) return null;
    final metadata = url.substring(0, commaIndex).toLowerCase();
    if (!metadata.contains(';base64')) return null;
    try {
      return base64Decode(url.substring(commaIndex + 1));
    } catch (_) {
      return null;
    }
  }

  /// Loads an image with proper CORS handling for web
  /// Falls back to standard loading for mobile platforms
  /// Returns graceful placeholder widget if imageUrl is null or empty
  static Widget loadImage({
    required String? imageUrl,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    // Handle null or empty URLs
    if (imageUrl == null || imageUrl.trim().isEmpty) {
      return _defaultPlaceholder(
        width: width,
        height: height,
        customWidget: errorWidget ?? placeholder,
      );
    }

    final sanitizedImageUrl = _sanitizeUrl(imageUrl);
    if (sanitizedImageUrl.isEmpty) {
      return _defaultPlaceholder(
        width: width,
        height: height,
        customWidget: errorWidget ?? placeholder,
      );
    }

    final decodedDataImage = _decodeDataImage(sanitizedImageUrl);

    if (decodedDataImage != null) {
      return Image.memory(
        decodedDataImage,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          return _defaultPlaceholder(
            width: width,
            height: height,
            customWidget: errorWidget,
          );
        },
      );
    }

    if (kIsWeb) {
      final isHttpUrl = sanitizedImageUrl.startsWith('http://') ||
          sanitizedImageUrl.startsWith('https://');
      final isAlreadyProxied = sanitizedImageUrl.contains('images.weserv.nl');

      Widget buildProxyFallback() {
        if (isHttpUrl && !isAlreadyProxied) {
          final proxyUrl =
              'https://images.weserv.nl/?url=${Uri.encodeComponent(sanitizedImageUrl)}';
          return Image.network(
            proxyUrl,
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) {
              return _defaultPlaceholder(
                width: width,
                height: height,
                customWidget: errorWidget,
              );
            },
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return placeholder ??
                  Container(
                    width: width,
                    height: height,
                    color: const Color(0xFFF3F4F6),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    ),
                  );
            },
          );
        }
        return _defaultPlaceholder(
          width: width,
          height: height,
          customWidget: errorWidget,
        );
      }

      // For web, use Image.network with proper error handling and automatic CORS proxy retry
      return Image.network(
        sanitizedImageUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          final shortenedUrl = sanitizedImageUrl.length > 140
              ? '${sanitizedImageUrl.substring(0, 140)}...'
              : sanitizedImageUrl;
          debugPrint('Image direct load failed (web CORS), retrying with proxy: $error | url=$shortenedUrl');
          return buildProxyFallback();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder ??
              Container(
                width: width,
                height: height,
                color: const Color(0xFFF3F4F6),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                ),
              );
        },
      );
    }

    // For native platforms, use Image.network
    return Image.network(
      sanitizedImageUrl,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        final shortenedUrl = sanitizedImageUrl.length > 140
              ? '${sanitizedImageUrl.substring(0, 140)}...'
              : sanitizedImageUrl;
        debugPrint('Image load error (native): $error | url=$shortenedUrl');
        return _defaultPlaceholder(
          width: width,
          height: height,
          customWidget: errorWidget,
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder ??
            Container(
              width: width,
              height: height,
              color: const Color(0xFFF3F4F6),
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
      },
    );
  }

  /// Loads a circular avatar image with CORS handling
  /// Returns fallback widget for null/empty URLs
  static Widget loadAvatar({
    String? imageUrl,
    required double radius,
    String? fallbackText,
    Color? backgroundColor,
    Color? textColor,
    BoxFit fit = BoxFit.cover,
    Alignment alignment = Alignment.center,
  }) {
    final resolvedBackgroundColor = backgroundColor ?? Colors.grey[400]!;
    final resolvedTextColor = textColor ?? _defaultAvatarTextColor(resolvedBackgroundColor);

    // Handle null or empty URLs with fallback
    if (imageUrl == null || imageUrl.trim().isEmpty) {
      return ClipOval(
        child: Container(
          width: radius * 2,
          height: radius * 2,
          color: resolvedBackgroundColor,
          child: Center(
            child: Text(
              fallbackText?.isNotEmpty == true
                  ? fallbackText![0].toUpperCase()
                  : 'U',
              style: TextStyle(
                color: resolvedTextColor,
                fontSize: radius * 0.8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: loadImage(
          imageUrl: imageUrl,
          width: radius * 2,
          height: radius * 2,
          fit: fit,
          alignment: alignment,
          errorWidget: Container(
            width: radius * 2,
            height: radius * 2,
            color: resolvedBackgroundColor,
            child: Center(
              child: Text(
                fallbackText?.isNotEmpty == true
                    ? fallbackText![0].toUpperCase()
                    : 'U',
                style: TextStyle(
                  color: resolvedTextColor,
                  fontSize: radius * 0.8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Creates an ImageProvider with proper CORS handling for web
  /// Returns null if imageUrl is null/empty
  static ImageProvider? getImageProvider(String? imageUrl) {
    if (imageUrl == null || imageUrl.trim().isEmpty) {
      return null;
    }

    final sanitizedImageUrl = _sanitizeUrl(imageUrl);

    return NetworkImage(sanitizedImageUrl);
  }
}
