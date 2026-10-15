# LinkedIn Analytics Dashboard

Flutter Web + Firestore dashboard for Rextech's weekly LinkedIn numbers. No login, free tier only.

## First-time setup

1. In the [Firebase console](https://console.firebase.google.com), create a project and enable **Firestore** (test mode is fine).
2. Install the FlutterFire CLI: `dart pub global activate flutterfire_cli`
3. In this folder: `firebase login`, then `flutterfire configure --platforms=web`
   (this replaces the placeholder `lib/firebase_options.dart`).
4. Put the project ID in `.firebaserc` (or run `firebase use --add`).
5. Publish the open rules: `firebase deploy --only firestore:rules`

## Deploy

```
flutter build web --release
firebase deploy --only hosting
```

## Local testing without a Firebase project

Requires Java 21+ (for example Android Studio's `jbr`).

```
firebase emulators:start --only firestore --project demo-linkedin-dashboard
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

`?page=0..4` in the URL opens Dashboard, Data Entry, Weeks, Employees or Settings directly.

## Note on security

The Firestore rules allow anyone with the URL to read and write. Keep the URL private,
and export a JSON backup regularly from Settings.
