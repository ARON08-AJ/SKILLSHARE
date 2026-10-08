import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/app_lock_provider.dart';
import 'providers/user_provider.dart';
import 'services/admin_bootstrap_service.dart';
import 'screens/splash_screen.dart';
import 'utils/app_theme.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/internet_required_gate.dart';
import 'firebase_options.dart';

void main() async {
  // Ensure Flutter binding is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Add error handler
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exception}');
    debugPrint('Stack trace: ${details.stack}');
  };

  // Gracefully handle UI build errors so users never see the red screen with yellow text glitch
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('Transient UI Build Error caught: ${details.exception}');
    return const SizedBox.shrink();
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error');
    debugPrint('Stack trace: $stack');
    return true;
  };

  bool firebaseInitialized = false;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    firebaseInitialized = true;
    debugPrint('✅ Firebase initialized successfully');

    // Configure Firestore settings based on platform
    if (kIsWeb) {
      // Web: keep persistence off to avoid intermittent watch-stream
      // assertion issues affecting chat listeners.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
      );
      debugPrint('✅ Firestore configured for web');
    } else {
      // Mobile: Enable offline persistence with unlimited cache
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint('✅ Firestore configured for mobile with offline persistence');
    }

    // Keep startup fast/stable on end-user devices.
    // Admin bootstrap can be enabled explicitly when needed.
    const bootstrapAdmin = bool.fromEnvironment(
      'SKILLSHARE_BOOTSTRAP_ADMIN',
      defaultValue: true,
    );
    if (bootstrapAdmin && kDebugMode) {
      unawaited(AdminBootstrapService().ensureDefaultAdminAccount());
    }
  } catch (e, stackTrace) {
    debugPrint('❌ Firebase initialization error: $e');
    debugPrint('Stack trace: $stackTrace');
    // Continue running app even if Firebase fails
    // The app will show error states where Firebase is needed
  }

  runApp(MyApp(firebaseInitialized: firebaseInitialized));
}

class MyApp extends StatelessWidget {
  final bool firebaseInitialized;

  const MyApp({super.key, this.firebaseInitialized = true});

  @override
  Widget build(BuildContext context) {
    if (!firebaseInitialized) {
      return MaterialApp(
        title: 'SkillShare',
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 60, color: Colors.red),
                const SizedBox(height: 20),
                const Text(
                  'Firebase Initialization Failed',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Please check your internet connection and Firebase configuration.',
                    textAlign: TextAlign.center,
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Reload the app
                    main();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
      ],
      child: MaterialApp(
        title: 'SkillShare',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
        builder: (context, child) {
          final guardedChild = SafeArea(
            top: false,
            left: false,
            right: false,
            bottom: false,
            child: child ?? const SizedBox.shrink(),
          );

          return ColoredBox(
            color: Colors.transparent,
            child: InternetRequiredGate(
              child: AppLockGate(
                child: guardedChild,
              ),
            ),
          );
        },
      ),
    );
  }
}
