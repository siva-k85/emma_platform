import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/app_user.dart';
import 'auth/providers.dart';

class RouteGuard {
  static bool canAccessAdmin(WidgetRef ref) => ref.read(roleProvider) == AppRole.admin;
  static bool canAccessResident(WidgetRef ref) => ref.read(roleProvider) == AppRole.resident;
  static bool canAccessAttending(WidgetRef ref) => ref.read(roleProvider) == AppRole.attending;
}

