import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'data/repository.dart';
import 'firebase_options.dart';
import 'shell.dart';
import 'theme.dart';

const _useEmulator = bool.fromEnvironment('USE_EMULATOR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter web only builds the semantics tree once something asks for it,
  // so screen readers and auditing tools see an empty page until the hidden
  // "Enable accessibility" button is pressed. Hold a handle for the whole
  // run of the app so the tree is there from the first frame.
  SemanticsBinding.instance.ensureSemantics();
  Object? startupError;
  if (_useEmulator) {
    // Local testing: `firebase emulators:start --only firestore` then
    // `flutter run -d chrome --dart-define=USE_EMULATOR=true`.
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'demo',
        appId: '1:0:web:0',
        messagingSenderId: '0',
        projectId: 'demo-linkedin-dashboard',
      ),
    );
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    Repository.instance.start();
  } else if (DefaultFirebaseOptions.web.apiKey == 'REPLACE_ME') {
    startupError = 'Firebase is not configured yet.\n\n'
        'Run `flutterfire configure` in the project folder, then rebuild.';
  } else {
    try {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
      Repository.instance.start();
    } catch (e) {
      startupError = 'Could not connect to Firebase:\n$e';
    }
  }
  runApp(LinkedInDashboardApp(startupError: startupError));
}

class LinkedInDashboardApp extends StatelessWidget {
  const LinkedInDashboardApp({super.key, this.startupError});
  final Object? startupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkedIn Analytics Dashboard',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.light,
      home: startupError == null
          ? const AppShell()
          : Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.settings_suggest_outlined,
                        size: 48, color: AppColors.primary),
                    const SizedBox(height: 16),
                    SelectableText('$startupError',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ]),
                ),
              ),
            ),
    );
  }
}
