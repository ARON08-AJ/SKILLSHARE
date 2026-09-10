import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../utils/app_fonts.dart';
import '../../widgets/google_g_logo.dart';
import '../../utils/app_dialog.dart';
import '../main_navigation.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  late final FocusNode _passwordFocusNode;

  // ── Animated gradient ──────────────────────────────────────────────────────
  late final AnimationController _gradCtrl;

  // Each phase is [topLeft, center, bottomRight]
  static const _phases = [
    [Color(0xFF6A11CB), Color(0xFF9C27B0), Color(0xFF2575FC)],
    [Color(0xFF1A237E), Color(0xFF3949AB), Color(0xFFE91E63)],
    [Color(0xFF00695C), Color(0xFF00897B), Color(0xFF1565C0)],
    [Color(0xFF4A148C), Color(0xFF7B1FA2), Color(0xFF00B0FF)],
  ];
  int _phase = 0;

  @override
  void initState() {
    super.initState();
    _gradCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() => _phase = (_phase + 1) % _phases.length);
          _gradCtrl.forward(from: 0);
        }
      });
    _gradCtrl.forward();
    _passwordFocusNode = FocusNode();
    _passwordFocusNode.addListener(() => setState(() {}));
    _emailController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _gradCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  // ── Animated page route ────────────────────────────────────────────────────
  static Route<T> _slideUpRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 500),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(position: slide, child: child),
        );
      },
    );
  }

  // ── Error dialog ────────────────────────────────────────────────────────────
  void _showErrorDialog(String message) {
    AppDialog.error(
      context,
      message,
      title: 'Sign In Failed',
      buttonText: 'Try Again',
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Smart email: append @gmail.com if user typed plain name
    String email = _emailController.text.trim();
    if (!email.contains('@')) {
      email = '$email@gmail.com';
    }

    final success = await authProvider.signIn(
      email: email,
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pushReplacement(
        _slideUpRoute(const MainNavigation()),
      );
    } else {
      _showErrorDialog(authProvider.error ?? 'Login failed. Please try again.');
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final success = await authProvider.signInWithGoogle();

    if (!mounted) return;

    if (success) {
      final user = authProvider.currentUser;
      if (user != null) {
        Navigator.of(context).pushReplacement(
          _slideUpRoute(const MainNavigation()),
        );
      }
    } else {
      _showErrorDialog(
          authProvider.error ?? 'Google sign-in failed. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        body: Stack(
          children: [
            // ── Animated gradient background ─────────────────────────────
            AnimatedBuilder(
              animation: _gradCtrl,
              builder: (_, __) {
                final t = _gradCtrl.value;
                final curr = _phases[_phase];
                final next = _phases[(_phase + 1) % _phases.length];
                final c1 = Color.lerp(curr[0], next[0], t)!;
                final c2 = Color.lerp(curr[1], next[1], t)!;
                final c3 = Color.lerp(curr[2], next[2], t)!;
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [c1, c2, c3],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                );
              },
            ),

            // ── Decorative blobs ─────────────────────────────────────────
            Positioned(
              top: -60,
              right: -60,
              child: _blob(260, Colors.white.withValues(alpha: 0.07)),
            ),
            Positioned(
              top: 80,
              left: -80,
              child: _blob(200, Colors.white.withValues(alpha: 0.05)),
            ),
            Positioned(
              bottom: 60,
              right: 40,
              child: _blob(140, Colors.white.withValues(alpha: 0.06)),
            ),
            Positioned(
              bottom: -40,
              left: -40,
              child: _blob(180, Colors.white.withValues(alpha: 0.04)),
            ),

            // ── Scrollable content ───────────────────────────────────────
            SafeArea(
              child: Center(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context)
                      .copyWith(scrollbars: false),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        children: [
                          // App name + tagline above the card
                          Text(
                            'SkillShare',
                            style: AppFonts.pacifico(
                              fontSize: 36,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Connect with skilled professionals',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.85),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // ── Card ─────────────────────────────────────────
                          Card(
                            elevation: 24,
                            shadowColor: Colors.black.withValues(alpha: 0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(28, 32, 28, 24),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Heading inside card
                                    const Text(
                                      'Welcome back!',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1A1A2E),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Sign in to continue',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[500],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 28),

                                    // ── Email ────────────────────────────
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [
                                        AutofillHints.email
                                      ],
                                      enableInteractiveSelection: true,
                                      textInputAction: TextInputAction.next,
                                      style: const TextStyle(fontSize: 15),
                                      onFieldSubmitted: (_) {
                                        _passwordFocusNode.requestFocus();
                                      },
                                      decoration: _inputDecoration(
                                        label: 'Email',
                                        icon: Icons.email_outlined,
                                      ).copyWith(
                                        hintText: 'username@gmail.com',
                                        hintStyle: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 14,
                                        ),
                                        suffixText: _emailController.text.isNotEmpty && !_emailController.text.contains('@')
                                            ? '@gmail.com'
                                            : null,
                                        suffixStyle: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) {
                                          return 'Please enter your email';
                                        }
                                        // Accept plain username (we append @gmail.com)
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),

                                    // ── Password ─────────────────────────
                                    TextFormField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      autofillHints: const [
                                        AutofillHints.password
                                      ],
                                      enableInteractiveSelection: true,
                                      textInputAction: TextInputAction.done,
                                      style: const TextStyle(fontSize: 15),
                                      focusNode: _passwordFocusNode,
                                      onFieldSubmitted: (_) {
                                        _handleLogin();
                                      },
                                      decoration: _inputDecoration(
                                        label: 'Password',
                                        icon: Icons.lock_outline,
                                      ).copyWith(
                                        suffixIcon: (_passwordFocusNode
                                                    .hasFocus ||
                                                _passwordController
                                                    .text.isNotEmpty)
                                            ? IconButton(
                                                icon: Icon(
                                                  _obscurePassword
                                                      ? Icons
                                                          .visibility_off_rounded
                                                      : Icons
                                                          .visibility_rounded,
                                                  color: _obscurePassword
                                                      ? Colors.grey[400]
                                                      : const Color(0xFF6A11CB),
                                                  size: 22,
                                                ),
                                                onPressed: () => setState(() =>
                                                    _obscurePassword =
                                                        !_obscurePassword),
                                              )
                                            : null,
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) {
                                          return 'Please enter your password';
                                        }
                                        return null;
                                      },
                                    ),

                                    // ── Forgot password ───────────────────
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4, horizontal: 0),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () async {
                                          final email =
                                              _emailController.text.trim();
                                          if (email.isEmpty) {
                                            AppDialog.info(
                                              context,
                                              'Enter your email address first. Password reset works for email/password accounts.',
                                            );
                                            return;
                                          }
                                          try {
                                            await AuthService()
                                                .resetPassword(email);
                                            if (context.mounted) {
                                              AppDialog.success(
                                                context,
                                                'If $email is an email/password account, Firebase will send a reset link. Check the inbox and spam folder. Google-only accounts should sign in with Google.',
                                              );
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              AppDialog.error(
                                                context,
                                                'Password reset failed',
                                                detail: e.toString(),
                                              );
                                            }
                                          }
                                        },
                                        child: const Text(
                                          'Forgot Password?',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF6A11CB),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),

                                    // ── Login Button ──────────────────────
                                    Consumer<AuthProvider>(
                                      builder: (context, authProvider, _) {
                                        return Container(
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [
                                                Color(0xFF6A11CB),
                                                Color(0xFF2575FC),
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF6A11CB)
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 12,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
                                          ),
                                          child: ElevatedButton(
                                            onPressed:
                                                authProvider.isEmailLoading
                                                    ? null
                                                    : _handleLogin,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.transparent,
                                              shadowColor: Colors.transparent,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 16),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                            ),
                                            child: authProvider.isEmailLoading
                                                ? const SizedBox(
                                                    height: 20,
                                                    width: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                                  Color>(
                                                              Colors.white),
                                                    ),
                                                  )
                                                : const Text(
                                                    'Login',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.white,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 24),

                                    // ── Divider ───────────────────────────
                                    Row(
                                      children: [
                                        Expanded(
                                            child: Divider(
                                                color: Colors.grey[300],
                                                thickness: 1)),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          child: Text(
                                            'OR',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[500],
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                            child: Divider(
                                                color: Colors.grey[300],
                                                thickness: 1)),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // ── Google Button ─────────────────────
                                    Consumer<AuthProvider>(
                                      builder: (context, authProvider, _) {
                                        return OutlinedButton.icon(
                                          onPressed:
                                              authProvider.isGoogleLoading
                                                  ? null
                                                  : _handleGoogleSignIn,
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 14),
                                            side: BorderSide(
                                                color: Colors.grey[300]!,
                                                width: 1.5),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            backgroundColor: Colors.grey[50],
                                          ),
                                          icon: authProvider.isGoogleLoading
                                              ? const SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2),
                                                )
                                              : const GoogleGLogo(size: 22),
                                          label: const Text(
                                            'Continue with Google',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF333333),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // ── Sign up link below card ────────────────────────
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Don't have an account? ",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 14,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const SignUpScreen()),
                                ),
                                child: const Text(
                                  'Sign Up',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
      {required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF6A11CB), size: 20),
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF6A11CB), width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.red, width: 1.8),
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
