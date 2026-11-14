import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter_example/error_example.dart';

import 'exception_steps_screen.dart';
import 'masking_tests_screen.dart';
import 'text_mask_policy_screen.dart';
import 'platform_view_spill_screen.dart';
import 'platform_views_screen.dart';
import 'survey_nested_navigator_screen.dart';

const kMaskAllPlatformViews = true;

TxlemetrySessionReplayConfig? exampleReplayConfig;

Future<void> main() async {
  final config = TxlemetryConfig(
    'phc_YOUR_PROJECT_TOKEN',
  );
  config.onFeatureFlags = () {
    debugPrint('[Txlemetry] Feature flags loaded!');
  };

  config.beforeSend = [
    (event) {
      debugPrint('[beforeSend] Event: ${event.event}');

      if (event.event == 'drop me') {
        debugPrint('[beforeSend] Dropping event: ${event.event}');
        return null;
      }

      if (event.event == 'modify me') {
        event.properties ??= {};
        event.properties?['modified_by_before_send'] = true;
        debugPrint('[beforeSend] Modified event: ${event.event}');
      }

      return event;
    },
  ];

  config.debug = true;
  config.captureApplicationLifecycleEvents = false;
  config.host = 'https://app.txlemetry.com';
  config.surveys = false;
  config.sessionReplay = true;
  config.sessionReplayConfig.maskAllTexts = false;
  config.sessionReplayConfig.maskAllImages = false;
  config.sessionReplayConfig.maskAllPlatformViews = kMaskAllPlatformViews;
  config.sessionReplayConfig.captureNativeScreens = true;
  config.sessionReplayConfig.throttleDelay = const Duration(milliseconds: 1000);
  exampleReplayConfig = config.sessionReplayConfig;
  config.flushAt = 1;

  config.errorTrackingConfig.captureFlutterErrors =
      true; // Capture Flutter framework errors
  config.errorTrackingConfig.capturePlatformDispatcherErrors =
      true; // Capture Dart runtime errors
  config.errorTrackingConfig.captureIsolateErrors =
      true; // Capture isolate errors
  config.errorTrackingConfig.captureNativeExceptions =
      true; // Capture native exceptions (Android & Apple platforms)

  if (kIsWeb) {
    runZonedGuarded(
      () async => await _initAndRun(config),
      (error, stackTrace) async => await Txlemetry().captureRunZonedGuardedError(
        error: error,
        stackTrace: stackTrace,
      ),
    );
  } else {
    await _initAndRun(config);
  }
}

Future<void> _initAndRun(TxlemetryConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Txlemetry().setup(config);
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return TxlemetryWidget(
      child: MaterialApp(
        navigatorObservers: [TxlemetryObserver()],
        title: 'Flutter App',
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.system,
        home: const InitialScreen(),
      ),
    );
  }
}

class InitialScreen extends StatefulWidget {
  const InitialScreen({super.key});

  @override
  InitialScreenState createState() => InitialScreenState();
}

class InitialScreenState extends State<InitialScreen> {
  static const _exampleChannel = MethodChannel('txlemetry_flutter_example');
  final _txlemetryFlutterPlugin = Txlemetry();
  dynamic _result = "";

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Txlemetry Flutter App')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SecondRoute(),
                        settings: const RouteSettings(name: 'second_route'),
                      ),
                    );
                  },
                  child: const TxlemetryMaskWidget(
                    child: Text('Go to Second Route'),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SurveyNestedNavigatorScreen(),
                        settings: const RouteSettings(
                          name: 'survey_nested_navigator',
                        ),
                      ),
                    );
                  },
                  child: const Text('Nested Navigator Survey'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MaskingTestsScreen(),
                        settings: const RouteSettings(name: 'masking_tests'),
                      ),
                    );
                  },
                  child: const Text('Masking Tests'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const TextMaskPolicyScreen(),
                        settings: const RouteSettings(name: 'text_mask_policy'),
                      ),
                    );
                  },
                  child: const Text('Text Mask Policy (Replay)'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ExceptionStepsScreen(),
                        settings: const RouteSettings(name: 'exception_steps'),
                      ),
                    );
                  },
                  child: const Text('Exception Steps'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PlatformViewsScreen(),
                        settings: const RouteSettings(name: 'platform_views'),
                      ),
                    );
                  },
                  child: const Text('Platform Views (Replay)'),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PlatformViewSpillScreen(),
                        settings: const RouteSettings(
                          name: 'platform_view_spill',
                        ),
                      ),
                    );
                  },
                  child: const Text('Platform View Spill (Replay)'),
                ),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Capture",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        _txlemetryFlutterPlugin.screen(
                          screenName: "my screen",
                          properties: {"foo": "bar"},
                        );
                      },
                      child: const Text("Capture Screen manually"),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        _txlemetryFlutterPlugin.capture(
                          eventName: "eventName",
                          properties: {"foo": "bar"},
                          userProperties: {"user_foo": "user_bar"},
                          userPropertiesSetOnce: {
                            "user_foo_once": "user_bar_once",
                          },
                        );
                      },
                      child: const Text("Capture Event"),
                    ),
                  ],
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Logs",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        _txlemetryFlutterPlugin.captureLog(
                          body: "checkout completed",
                          level: TxlemetryLogSeverity.info,
                          attributes: {"order_id": "ord_789"},
                        );
                      },
                      child: const Text("Capture Log (info)"),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        _txlemetryFlutterPlugin.logger.error("payment failed", {
                          "error_code": "E001",
                        });
                      },
                      child: const Text("logger.error"),
                    ),
                  ],
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Activity",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () {
                        _txlemetryFlutterPlugin.optOut();
                      },
                      child: const Text("Disable Capture"),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () {
                        _txlemetryFlutterPlugin.optIn();
                      },
                      child: const Text("Enable Capture"),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                      onPressed: () async {
                        final isOptedOut = await _txlemetryFlutterPlugin
                            .isOptOut();
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Opted out: $isOptedOut'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Text("Check Opt-Out Status"),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.register("foo", "bar");
                  },
                  child: const Text("Register"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.unregister("foo");
                  },
                  child: const Text("Unregister"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.group(
                      groupType: "theType",
                      groupKey: "theKey",
                      groupProperties: {"foo": "bar"},
                    );
                  },
                  child: const Text("Group"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.setPersonPropertiesForFlags({
                      "storefront_country": "US",
                      "demand_score": 88,
                    });
                  },
                  child: const Text("Set person properties for flags"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.resetPersonPropertiesForFlags();
                  },
                  child: const Text("Reset person properties for flags"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.setGroupPropertiesForFlags(
                      "theType",
                      {"is_enterprise": true},
                    );
                  },
                  child: const Text("Set group properties for flags"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.resetGroupPropertiesForFlags();
                  },
                  child: const Text("Reset group properties for flags"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.identify(
                      userId: "myId",
                      userProperties: {"foo": "bar"},
                      userPropertiesSetOnce: {"foo1": "bar1"},
                    );
                  },
                  child: const Text("Identify"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.alias(alias: "myAlias");
                  },
                  child: const Text("Alias"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.debug(true);
                  },
                  child: const Text("Debug"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.reset();
                  },
                  child: const Text("Reset"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.flush();
                  },
                  child: const Text("Flush"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final result = await _txlemetryFlutterPlugin.getDistinctId();
                    setState(() {
                      _result = result;
                    });
                  },
                  child: const TxlemetryMaskWidget(child: Text("distinctId")),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Session Recording",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () async {
                        await _txlemetryFlutterPlugin.startSessionRecording();
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Session recording started (resume current)',
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Text("Start Recording"),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                      onPressed: () async {
                        await _txlemetryFlutterPlugin.startSessionRecording(
                          resumeCurrent: false,
                        );
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Session recording started (new session)',
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Text("Start New Session"),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () async {
                        await _txlemetryFlutterPlugin.stopSessionRecording();
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Session recording stopped'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Text("Stop Recording"),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                      onPressed: () async {
                        final isActive = await _txlemetryFlutterPlugin
                            .isSessionReplayActive();
                        if (mounted && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Session replay active: $isActive'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Text("Check Active"),
                    ),
                  ],
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Error Tracking - Manual",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await ErrorExample().causeHandledDivisionError();
                  },
                  child: const Text("Capture Exception"),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Error Tracking - Autocapture",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Flutter error triggered! Check Txlemetry.',
                          ),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }

                    // Test Flutter error handler by throwing in widget context
                    ErrorExample().causeUnhandledDivisionError();
                  },
                  child: const Text("Test Flutter Error Handler"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    await ErrorExample().throwWithinDelayed();

                    if (mounted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Dart runtime error triggered! Check Txlemetry.',
                          ),
                          backgroundColor: Colors.blue,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  child: const Text("Test Dart Error Handler"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    // Test isolate error listener by throwing in an async callback
                    await ErrorExample().throwWithinTimer();

                    if (mounted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Isolate error triggered! Check Txlemetry.',
                          ),
                          backgroundColor: Colors.purple,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                  child: const Text("Test Isolate Error Handler"),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (mounted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Native crash triggered! The app will crash. '
                            'The exception will be sent on next launch.',
                          ),
                          backgroundColor: Colors.deepOrange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }

                    // Give the snackbar time to show before crashing
                    await Future.delayed(const Duration(seconds: 1));

                    // Trigger a native crash via method channel
                    await _exampleChannel.invokeMethod('triggerNativeCrash');
                  },
                  child: const Text("Test Native Crash (will crash app!)"),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "beforeSend Tests",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.spaceEvenly,
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        _txlemetryFlutterPlugin.capture(
                          eventName: 'normal_event',
                          properties: {'test': 'pass_through'},
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Normal event sent (should appear in Txlemetry)',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text("Normal Event"),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _txlemetryFlutterPlugin.capture(
                          eventName: 'drop me',
                          properties: {'should_be': 'dropped'},
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Drop event sent (should NOT appear in Txlemetry)',
                            ),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text("Drop Event"),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        _txlemetryFlutterPlugin.capture(
                          eventName: 'modify me',
                          properties: {'original': true},
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Modify event sent (check for modified_by_before_send property)',
                            ),
                            backgroundColor: Colors.orange,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: const Text("Modify Event"),
                    ),
                  ],
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Feature flags",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final result = await _txlemetryFlutterPlugin.getFeatureFlag(
                      "feature_name",
                    );
                    setState(() {
                      _result = result;
                    });
                  },
                  child: const Text("Get Feature Flag status"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final result = await _txlemetryFlutterPlugin.isFeatureEnabled(
                      "feature_name",
                    );
                    setState(() {
                      _result = result;
                    });
                  },
                  child: const Text("isFeatureEnabled"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final result = await _txlemetryFlutterPlugin
                        .getFeatureFlagResult("feature_name");
                    setState(() {
                      _result = result?.payload?.toString();
                    });
                  },
                  child: const Text("getFeatureFlagPayload"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final result = await _txlemetryFlutterPlugin
                        .getFeatureFlagResult("feature_name");
                    setState(() {
                      _result = result?.toString();
                    });
                  },
                  child: const Text("getFeatureFlagResult"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await _txlemetryFlutterPlugin.reloadFeatureFlags();
                  },
                  child: const TxlemetryMaskWidget(
                    child: Text("reloadFeatureFlags"),
                  ),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    "Data result",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(_result.toString()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SecondRoute extends StatefulWidget {
  const SecondRoute({super.key});

  @override
  SecondRouteState createState() => SecondRouteState();
}

class SecondRouteState extends State<SecondRoute> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TxlemetryMaskWidget(child: Text('First Route')),
      ),
      body: Center(
        child: RepaintBoundary(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                child: const TxlemetryMaskWidget(child: Text('Open route')),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ThirdRoute(),
                      settings: const RouteSettings(name: 'third_route'),
                    ),
                  ).then((_) {});
                },
              ),
              const SizedBox(height: 20),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Sensitive Text Input',
                  hintText: 'Enter sensitive data',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              TxlemetryMaskWidget(
                child: Image.asset('assets/training_txlemetry.png', height: 200),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class ThirdRoute extends StatelessWidget {
  const ThirdRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Third Route')),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 10.0,
            mainAxisSpacing: 10.0,
          ),
          itemCount: 16,
          itemBuilder: (context, index) {
            return Image.asset('assets/txlemetry_logo.png', fit: BoxFit.cover);
          },
        ),
      ),
    );
  }
}

/// Custom exception class for demonstration purposes
class CustomException implements Exception {
  final String message;
  final String? code;
  final Map<String, dynamic>? additionalData;

  const CustomException(this.message, {this.code, this.additionalData});

  @override
  String toString() {
    if (code != null) {
      return 'CustomException($code): $message $additionalData';
    }
    return 'CustomException: $message $additionalData';
  }
}
