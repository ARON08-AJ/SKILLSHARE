import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_constants.dart';
import '../../utils/app_fonts.dart';
import '../../widgets/google_g_logo.dart';
import '../main_navigation.dart';
import '../profile/skilled_user_setup_screen.dart';
import '../profile/customer_setup_screen.dart';
import '../profile/company_setup_screen.dart';
import '../../utils/app_dialog.dart';
import 'login_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String _selectedRole = AppConstants.roleCustomer;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  late final FocusNode _passwordFocusNode;
  late final FocusNode _confirmPasswordFocusNode;

  // â”€â”€ Animated gradient (same phases as login) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  late final AnimationController _gradCtrl;
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
    _confirmPasswordFocusNode = FocusNode();
    _passwordFocusNode.addListener(() => setState(() {}));
    _confirmPasswordFocusNode.addListener(() => setState(() {}));
    _emailController.addListener(() => setState(() {}));
    _passwordController.addListener(() => setState(() {}));
    _confirmPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _gradCtrl.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  // ── Animated page route ─────────────────────────────────────────────────────
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
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return SlideTransition(
          position: slide,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  // ── Error dialog ─────────────────────────────────────────────────────────────
  void _showErrorDialog(String message) {
    AppDialog.error(
      context,
      message,
      title: 'Sign Up Failed',
      buttonText: 'Try Again',
    );
  }

  // ── Success dialog ───────────────────────────────────────────────────────────
  Future<void> _showSuccessDialog(String name, VoidCallback onContinue) async {
    await AppDialog.success(
      context,
      "Your account is ready. Let's set up your profile!",
      title: 'Welcome Aboard!',
      buttonText: 'Continue to Setup',
      onDismiss: onContinue,
    );
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Smart email: append @gmail.com if user typed plain name
    String email = _emailController.text.trim();
    if (!email.contains('@')) {
      email = '$email@gmail.com';
    }

    final success = await authProvider.signUp(
      email: email,
      password: _passwordController.text,
      name: _nameController.text.trim(),
      role: _selectedRole,
      phone: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      final userId = authProvider.currentUser!.uid;
      final name = _nameController.text.trim();

      void navigate() {
        if (!mounted) return;
        if (_selectedRole == AppConstants.roleSkilledUser) {
          Navigator.of(context).pushReplacement(
              _slideUpRoute(SkilledUserSetupScreen(userId: userId)));
        } else if (_selectedRole == AppConstants.roleCustomer) {
          Navigator.of(context).pushReplacement(
              _slideUpRoute(CustomerSetupScreen(userId: userId)));
        } else if (_selectedRole == AppConstants.roleCompany) {
          Navigator.of(context).pushReplacement(
              _slideUpRoute(CompanySetupScreen(userId: userId)));
        } else {
          Navigator.of(context)
              .pushReplacement(_slideUpRoute(const MainNavigation()));
        }
      }

      await _showSuccessDialog(name, navigate);
    } else {
      _showErrorDialog(
          authProvider.error ?? 'Sign up failed. Please try again.');
    }
  }

  Future<void> _handleGoogleSignIn() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success =
        await authProvider.signInWithGoogle(defaultRole: _selectedRole);
    if (!mounted) return;
    if (success) {
      Navigator.of(context)
          .pushReplacement(_slideUpRoute(const MainNavigation()));
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
            // â”€â”€ Animated gradient background â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

            // â”€â”€ Decorative blobs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

            // â”€â”€ Scrollable content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                          // Brand name
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
                            'Create your account',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.85),
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 28),

                          // â”€â”€ Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                          Card(
                            elevation: 24,
                            shadowColor: Colors.black.withValues(alpha: 0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(28, 28, 28, 20),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Heading
                                    const Text(
                                      'Join SkillShare',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1A1A2E),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Fill in the details below',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[500]),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 22),

                                    // Full Name
                                    TextFormField(
                                      controller: _nameController,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      style: const TextStyle(fontSize: 15),
                                      decoration: _inputDecoration(
                                        label: 'Full Name',
                                        icon: Icons.person_outlined,
                                      ),
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                              ? 'Please enter your name'
                                              : null,
                                    ),
                                    const SizedBox(height: 14),

                                    // Email
                                    TextFormField(
                                      controller: _emailController,
                                      keyboardType: TextInputType.emailAddress,
                                      style: const TextStyle(fontSize: 15),
                                      decoration: _inputDecoration(
                                        label: 'Email',
                                        icon: Icons.email_outlined,
                                      ).copyWith(
                                        hintText: 'username@gmail.com',
                                        hintStyle: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 14),
                                        suffixText: _emailController.text.isNotEmpty && !_emailController.text.contains('@')
                                            ? '@gmail.com'
                                            : null,
                                        suffixStyle: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                              ? 'Please enter your email'
                                              : null,
                                    ),
                                    const SizedBox(height: 14),

                                    // Phone (optional)
                                    TextFormField(
                                      controller: _phoneController,
                                      keyboardType: TextInputType.phone,
                                      style: const TextStyle(fontSize: 15),
                                      decoration: _inputDecoration(
                                        label: 'Phone (Optional)',
                                        icon: Icons.phone_outlined,
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // Role
                                    DropdownButtonFormField<String>(
                                      value: _selectedRole,
                                      isExpanded: true,
                                      style: AppFonts.lora(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFF1A1A2E),
                                      ),
                                      decoration: _inputDecoration(
                                        label: 'I am a',
                                        icon: null,
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: AppConstants.roleCustomer,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.person_outline,
                                                  size: 20,
                                                  color: Color(0xFF6A11CB)),
                                              SizedBox(width: 10),
                                              Text('Customer',
                                                  style: TextStyle(
                                                      fontSize: 15,
                                                      fontFamily:
                                                          'SourceSerif4')),
                                            ],
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: AppConstants.roleSkilledUser,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.engineering,
                                                  size: 20,
                                                  color: Color(0xFF6A11CB)),
                                              SizedBox(width: 10),
                                              Text('Skilled Professional',
                                                  style: TextStyle(
                                                      fontSize: 15,
                                                      fontFamily:
                                                          'SourceSerif4')),
                                            ],
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: AppConstants.roleCompany,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.business,
                                                  size: 20,
                                                  color: Color(0xFF6A11CB)),
                                              SizedBox(width: 10),
                                              Text('Company',
                                                  style: TextStyle(
                                                      fontSize: 15,
                                                      fontFamily:
                                                          'SourceSerif4')),
                                            ],
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: AppConstants
                                              .roleDeliveryPartner,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                  Icons
                                                      .local_shipping_outlined,
                                                  size: 20,
                                                  color: Color(0xFF6A11CB)),
                                              SizedBox(width: 10),
                                              Text('Delivery Partner',
                                                  style: TextStyle(
                                                      fontSize: 15,
                                                      fontFamily:
                                                          'SourceSerif4')),
                                            ],
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _selectedRole = v!),
                                    ),
                                    const SizedBox(height: 14),

                                    // Password
                                    TextFormField(
                                      controller: _passwordController,
                                      focusNode: _passwordFocusNode,
                                      obscureText: _obscurePassword,
                                      style: const TextStyle(fontSize: 15),
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
                                          return 'Please enter a password';
                                        }
                                        if (v.length < 6) {
                                          return 'Minimum 6 characters';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 14),

                                    // Confirm Password
                                    TextFormField(
                                      controller: _confirmPasswordController,
                                      focusNode: _confirmPasswordFocusNode,
                                      obscureText: _obscureConfirmPassword,
                                      style: const TextStyle(fontSize: 15),
                                      decoration: _inputDecoration(
                                        label: 'Confirm Password',
                                        icon: Icons.lock_outline,
                                      ).copyWith(
                                        suffixIcon: (_confirmPasswordFocusNode
                                                    .hasFocus ||
                                                _confirmPasswordController
                                                    .text.isNotEmpty)
                                            ? IconButton(
                                                icon: Icon(
                                                  _obscureConfirmPassword
                                                      ? Icons
                                                          .visibility_off_rounded
                                                      : Icons
                                                          .visibility_rounded,
                                                  color: _obscureConfirmPassword
                                                      ? Colors.grey[400]
                                                      : const Color(0xFF6A11CB),
                                                  size: 22,
                                                ),
                                                onPressed: () => setState(() =>
                                                    _obscureConfirmPassword =
                                                        !_obscureConfirmPassword),
                                              )
                                            : null,
                                      ),
                                      validator: (v) =>
                                          v != _passwordController.text
                                              ? 'Passwords do not match'
                                              : null,
                                    ),
                                    const SizedBox(height: 22),

                                    // Sign Up button
                                    Consumer<AuthProvider>(
                                      builder: (context, auth, _) {
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
                                            onPressed: auth.isLoading
                                                ? null
                                                : _handleSignUp,
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
                                            child: auth.isLoading
                                                ? const SizedBox(
                                                    height: 20,
                                                    width: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation(
                                                              Colors.white),
                                                    ),
                                                  )
                                                : const Text(
                                                    'Create Account',
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
                                    const SizedBox(height: 20),

                                    // OR divider
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
                                    const SizedBox(height: 16),

                                    // Google button
                                    Consumer<AuthProvider>(
                                      builder: (context, auth, _) {
                                        return OutlinedButton.icon(
                                          onPressed: auth.isLoading
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
                                          icon: auth.isLoading
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

                          // Already have account
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Already have an account? ',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 14,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.of(context)
                                    .pushReplacement(MaterialPageRoute(
                                        builder: (_) => const LoginScreen())),
                                child: const Text(
                                  'Login',
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
      {required String label, required IconData? icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: AppFonts.lora(
        color: Colors.grey[600],
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: icon != null
          ? Icon(icon, color: const Color(0xFF6A11CB), size: 20)
          : null,
      filled: true,
      fillColor: Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
