import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options_web.dart';

Future<void> _initFirebase() async {
  if (kIsWeb) {
    await Firebase.initializeApp(options: firebaseOptionsWeb);
  } else {
    await Firebase.initializeApp();
  }

  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

  if (kIsWeb) {
    await FirebaseMessaging.instance.getToken(vapidKey: fcmVapidKeyWeb);
  } else {
    await FirebaseMessaging.instance.requestPermission();
    await FirebaseMessaging.instance.getToken();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebase();
  runApp(const ProviderScope(child: EmmaApp()));
}
