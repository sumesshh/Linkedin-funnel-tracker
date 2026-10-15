// Firebase config for the `linkedin-funnel-tracker` project (web app "dashboard").
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {

  static FirebaseOptions get currentPlatform => web;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAcpNfQIJV0TewL9FgxtphcfQjUFhkoUFE',
    appId: '1:452676843635:web:dc81998ea44ecaa9631206',
    messagingSenderId: '452676843635',
    projectId: 'linkedin-funnel-tracker',
    authDomain: 'linkedin-funnel-tracker.firebaseapp.com',
    storageBucket: 'linkedin-funnel-tracker.firebasestorage.app',
    measurementId: 'G-H5CBHTLT59',
  );
}
