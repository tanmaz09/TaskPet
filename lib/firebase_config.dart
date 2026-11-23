/// Fill these two values in once your Firebase project exists
/// (Firebase console > Project settings > General).
///
/// While they still start with YOUR_, the app runs exactly as before and
/// all online features stay switched off.
///
/// The Web API key is not a password. It only tells Google which project to
/// talk to, so it is fine to keep it in the repo. What protects your data is
/// the Firestore security rules.
class FirebaseConfig {
  static const String projectId = 'YOUR_PROJECT_ID';
  static const String apiKey = 'YOUR_WEB_API_KEY';

  static bool get isConfigured =>
      !projectId.startsWith('YOUR_') && !apiKey.startsWith('YOUR_');
}
