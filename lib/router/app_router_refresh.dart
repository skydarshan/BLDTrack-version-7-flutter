import 'package:flutter/foundation.dart';

/// Notifies GoRouter when auth or org workspace access changes.
class AppRouterRefresh extends ChangeNotifier {
  AppRouterRefresh(this._auth, this._org) {
    _auth.addListener(notifyListeners);
    _org.addListener(notifyListeners);
  }

  final ChangeNotifier _auth;
  final ChangeNotifier _org;

  @override
  void dispose() {
    _auth.removeListener(notifyListeners);
    _org.removeListener(notifyListeners);
    super.dispose();
  }
}
