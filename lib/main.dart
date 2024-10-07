import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

  var logger = Logger();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final messagingInstance = FirebaseMessaging.instance;
  await messagingInstance.requestPermission();

  // final fcmToken = await messagingInstance.getToken();
  // debugPrint('FCM TOKEN: $fcmToken');

  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  if (Platform.isAndroid) {
    final androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        'default_notification_channel',
        'プッシュ通知のチャンネル名',
        importance: Importance.max,
      ),
    );
  }

  await _initNotification(callbackRouter: _navigateBasedOnMessage);

  final RemoteMessage? initialMessage =
      await FirebaseMessaging.instance.getInitialMessage();

  if (initialMessage != null) {
    print('アプリが停止している状態で通知を受信しました');

    _handleMessage(
      message: initialMessage,
      callbackRouter: _navigateBasedOnMessage,
    );
  }

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewApp(),
    ),
  );
}

void _handleMessage({
  required RemoteMessage message,
  required Function(Map<String, dynamic>) callbackRouter,
}) {
  final data = message.data;
  print('通知受信: $data');
  callbackRouter(data);
}

Future<void> _initNotification({
  required Function(Map<String, dynamic>) callbackRouter,
}) async {
  final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleMessage(message: message, callbackRouter: callbackRouter);
  });

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null && Platform.isAndroid) {
      await flutterLocalNotificationsPlugin.show(
        0,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            'default_notification_channel',
            'プッシュ通知のチャンネル名',
            importance: Importance.max,
            icon: android?.smallIcon,
          ),
        ),
        payload: json.encode(message.data),
      );
    }
  });

  flutterLocalNotificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (details) {
      if (details.payload != null) {
        final payloadMap =
            json.decode(details.payload!) as Map<String, dynamic>;
        debugPrint(payloadMap.toString());
        callbackRouter(payloadMap);
      }
    },
  );
}

void _navigateBasedOnMessage(Map<String, dynamic> data) {
  logger.d('receive $data');
  if (data['type'] == 'specificPage') {
    // 特定のページに遷移する処理
  }
}

class WebViewApp extends StatefulWidget {
  const WebViewApp({super.key});

  @override
  State<WebViewApp> createState() => _WebViewAppState();
}

class _WebViewAppState extends State<WebViewApp> {
  late final WebViewController _controller;
  late final PlatformWebViewControllerCreationParams params;

  @override
  void initState() {
    super.initState();
    //Basic認証に関する処理
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    // _controller = WebViewController()
    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel("ctmapp", onMessageReceived: (result) async {
        // result.message でJSからのデータを取得可能
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) async {
            // 特定のURLをフックして処理を追加

            if (request.url.contains('https://stgv2.poitore.town') ||
                request.url.contains('/support') ||
                request.url.contains('/applicant')) {
              final Uri url = Uri.parse(request.url);

              // ユーザー名とパスワードをBase64エンコード
              await launchUrl(url, mode: LaunchMode.externalApplication);
              // 認証情報をヘッダーに追加してWebViewをリクエスト
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            logger.d('Page loading: $url');
          },
          onPageFinished: (String url) {
            logger.d('Page loaded: $url');
          },
          onWebResourceError: (WebResourceError error) {
            logger.d('Error: ${error.description}');
            if (error.errorCode == -2) {
              logger.d('Too many retries, check network or server status.');
            }
          },
          onHttpAuthRequest: (HttpAuthRequest request) {
            request.onProceed(
              const WebViewCredential(
                user: '',
                password: '',
              ),
            );
          },
        ),
      );
    _loadBasicAuthPage();
  }

  void _loadBasicAuthPage() async {
    // var deviceId = Platform.isAndroid ? await FirebaseMessaging.instance.getToken() : await FirebaseMessaging.instance.getAPNSToken();
    var deviceId = await FirebaseMessaging.instance.getToken() ;
    var did = deviceId != null ? '?did=$deviceId' : "";
    var url = 'https://stg.moment-trading-card.market/$did';
    logger.d('url=$url');
    _controller.loadRequest(
      Uri.parse(url),
    );
  }

  // JavaScriptを実行するための関数
  void _executeJavaScript() {
    _controller.runJavaScript('alert("Hello from Flutter!");');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
          preferredSize: const Size.fromHeight(0.0), // ここを適切な高さに変更
          child: AppBar(
            backgroundColor: Colors.black,
            actions: [
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: _executeJavaScript, // ボタン押下時にJavaScriptを実行
              ),
            ],
          )),
      body: WebViewWidget(controller: _controller),
    );
  }
}
