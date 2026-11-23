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
  static const String projectId = 'taskpet-b8f3b';
  static const String apiKey = 'AIzaSyAJYwW7AG3YabMYm7OlO8FNEEW5FSTSPLM';

  static bool get isConfigured =>
      !projectId.startsWith('YOUR_') && !apiKey.startsWith('YOUR_');
}
