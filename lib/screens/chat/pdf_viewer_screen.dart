import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

/// ─── NativeLauncher ──────────────────────────────────────────────────────────
/// Bypasses url_launcher's Pigeon API (which fails on Vivo/MediaTek devices)
/// and calls Android's startActivity via a dedicated MethodChannel.
class _NativeLauncher {
  static const _channel = MethodChannel('com.skillshare.app/native_launcher');

  static Future<bool> launchUrl(String url) async {
    try {
      final result = await _channel.invokeMethod<bool>('launchUrl', {'url': url});
      return result ?? false;
    } catch (e) {
      debugPrint('[NativeLauncher] launchUrl failed: $e');
      return false;
    }
  }
}

/// ─── PdfViewerScreen ─────────────────────────────────────────────────────────
class PdfViewerScreen extends StatefulWidget {
  final String pdfUrl;
  final String title;

  const PdfViewerScreen({
    super.key,
    required this.pdfUrl,
    this.title = 'Offer Letter',
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  bool _sfViewerFailed = false;  // true → fall back to Google Docs
  String _errorMessage = '';
  Uint8List? _pdfBytes;

  /// Always serve over HTTPS — Cloudinary http:// URLs redirect to https anyway
  String get _safeUrl {
    final raw = widget.pdfUrl.trim();
    if (raw.startsWith('http://')) {
      return raw.replaceFirst('http://', 'https://');
    }
    return raw;
  }

  /// Google Docs online PDF viewer (no plugin required)
  String get _googleDocsUrl =>
      'https://docs.google.com/viewer?url=${Uri.encodeComponent(_safeUrl)}&embedded=true';

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  /// Download PDF bytes and validate the %PDF header
  Future<void> _loadPdf() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
      _sfViewerFailed = false;
      _errorMessage = '';
    });

    try {
      final uri = Uri.tryParse(_safeUrl);
      if (uri == null) throw Exception('Invalid document URL');

      // Add headers that Cloudinary respects for direct-download
      final response = await http.get(uri, headers: {
        'Accept': 'application/pdf,*/*',
        'User-Agent': 'SkillShareApp/1.0',
      }).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bytes = response.bodyBytes;

        // Validate PDF magic bytes: %PDF
        final isPdf = bytes.length >= 4 &&
            bytes[0] == 0x25 && // %
            bytes[1] == 0x50 && // P
            bytes[2] == 0x44 && // D
            bytes[3] == 0x46;   // F

        if (!isPdf) {
          // Cloudinary may return a redirect or HTML if PDF delivery is disabled.
          // In that case, fall straight through to Google Docs viewer.
          debugPrint('[PDF] Bytes do NOT start with %PDF — using Google Docs fallback');
          if (mounted) {
            setState(() {
              _pdfBytes = null;
              _sfViewerFailed = true;
              _isLoading = false;
            });
          }
          return;
        }

        if (mounted) {
          setState(() {
            _pdfBytes = bytes;
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Download failed (HTTP ${response.statusCode})');
      }
    } catch (e) {
      debugPrint('[PDF] Load error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  /// Open PDF in the device browser (Chrome / system browser) via native channel
  Future<void> _openExternal() async {
    // Try Google Docs viewer first — works without any PDF app
    final docsUrl = _googleDocsUrl;
    final launched = await _NativeLauncher.launchUrl(docsUrl);

    if (!launched) {
      // Fallback: open the raw Cloudinary URL
      final rawLaunched = await _NativeLauncher.launchUrl(_safeUrl);
      if (!rawLaunched && mounted) {
        // Last resort: copy to clipboard
        await Clipboard.setData(ClipboardData(text: _safeUrl));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Link copied to clipboard — paste it in Chrome to view the PDF'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  /// Called when SfPdfViewer cannot render the PDF
  void _onSfViewerFailed(String reason) {
    debugPrint('[PDF] SfPdfViewer failed: $reason — switching to Google Docs viewer');
    if (mounted) {
      setState(() {
        _sfViewerFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        actions: [
          IconButton(
            tooltip: 'Open in Browser',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: _openExternal,
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _openExternal,
              icon: const Icon(Icons.open_in_browser_rounded, size: 20),
              label: const Text(
                'Open in PDF Viewer / Drive',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A11CB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoader();
    if (_hasError) return _buildErrorCard();

    // ── Layer 1: SfPdfViewer (native renderer, best quality) ─────────────────
    if (_pdfBytes != null && !_sfViewerFailed) {
      return _buildSfViewer();
    }

    // ── Layer 2: Google Docs online viewer (no plugin required) ───────────────
    // Opens in Chrome via the "Open in Browser" button. We show a message here.
    return _buildGoogleDocsPrompt();
  }

  Widget _buildLoader() {
    return Container(
      color: Colors.white,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6A11CB)),
            ),
            SizedBox(height: 16),
            Text(
              'Loading Offer Letter...',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF555555),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSfViewer() {
    return SfPdfViewer.memory(
      _pdfBytes!,
      canShowScrollHead: true,
      canShowScrollStatus: true,
      onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
        _onSfViewerFailed(details.error);
      },
    );
  }

  /// Shown when bytes were downloaded but SfPdfViewer failed to render OR
  /// when Cloudinary returned non-PDF bytes (PDF delivery may be disabled).
  Widget _buildGoogleDocsPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6A11CB).withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 48,
                    color: Color(0xFF6A11CB),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Open PDF in Browser',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Tap the button below to view the offer letter in Google Docs or your browser.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openExternal,
                    icon: const Icon(Icons.open_in_browser_rounded),
                    label: const Text(
                      'Open in Google Docs / Chrome',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A11CB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _loadPdf,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry loading'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6A11CB),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 44,
                    color: Color(0xFFE53935),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Unable to load document',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage.isNotEmpty
                      ? _errorMessage
                      : 'Network error — check your connection and try again.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6A11CB),
                        side: const BorderSide(color: Color(0xFF6A11CB)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      onPressed: _loadPdf,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                      label: const Text('Open in Browser'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6A11CB),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                      onPressed: _openExternal,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
