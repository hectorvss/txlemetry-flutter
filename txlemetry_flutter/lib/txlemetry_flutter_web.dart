// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:txlemetry_flutter/src/error_tracking/dart_exception_processor.dart';
import 'package:txlemetry_flutter/src/util/logging.dart';
import 'package:txlemetry_flutter/src/utils/property_normalizer.dart';

import 'src/feature_flag_result.dart';
import 'src/logs/txlemetry_log_severity.dart';
import 'src/txlemetry_config.dart';
import 'src/txlemetry_constants.dart';
import 'src/txlemetry_event.dart';
import 'src/txlemetry_flutter_platform_interface.dart';
import 'src/txlemetry_flutter_web_handler.dart';
import 'src/utils/before_send.dart';
import 'src/replay/web/web_canvas_mask_provider.dart';
import 'src/utils/capture_utils.dart';

/// A web implementation of the TxlemetryFlutterPlatform of the TxlemetryFlutter plugin.
class TxlemetryFlutterWeb extends TxlemetryFlutterPlatformInterface {
  /// Constructs a TxlemetryFlutterWeb
  TxlemetryFlutterWeb();

  /// Stored configuration for accessing inAppIncludes and other settings
  TxlemetryConfig? _config;

  /// Copied at setup. Event beforeSend runs here, before txlemetry-js, the same
  /// way [TxlemetryFlutterIO] runs it before the platform channel.
  List<BeforeSendCallback> _beforeSendCallbacks = [];

  Future<TxlemetryEvent?> _runBeforeSend(
    String eventName,
    Map<String, Object>? properties, {
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) {
    return applyBeforeSend(
      _beforeSendCallbacks,
      TxlemetryEvent(
        event: eventName,
        properties: properties,
        userProperties: userProperties,
        userPropertiesSetOnce: userPropertiesSetOnce,
      ),
    );
  }

  static void registerWith(Registrar registrar) {
    final channel = MethodChannel(
      'txlemetry_flutter',
      const StandardMethodCodec(),
      registrar,
    );
    final instance = TxlemetryFlutterWeb();
    channel.setMethodCallHandler(instance.handleMethodCall);

    // Set the platform instance so that Txlemetry() can call methods directly
    // on the web implementation instead of going through the method channel.
    // This is required because method channels can only pass serializable data,
    // not function callbacks like onFeatureFlags.
    TxlemetryFlutterPlatformInterface.instance = instance;
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    // The 'setup' call is now handled by the setup method override.
    // Other method calls are delegated to handleWebMethodCall.
    if (call.method == 'setup') {
      // This case should ideally not be hit if Txlemetry().setup directly calls the overridden setup.
      // However, to be safe, we can log or ignore.
      // For now, let's assume direct call to overridden setup handles it.
      return null;
    }
    return handleWebMethodCall(call);
  }

  @override
  Future<void> setup(TxlemetryConfig config) async {
    // It's assumed txlemetry-js is initialized by the user in their HTML.
    // This setup primarily hooks into the existing txlemetry-js instance.

    // If projectToken and host are in config, and txlemetry.init is to be handled by plugin:
    // This is an example if we wanted the plugin to also call txlemetry.init()
    // final jsOptions = <String, dynamic>{
    //   'api_host': config.host,
    //   // Add other relevant options from TxlemetryConfig if needed for JS init
    // }.jsify();
    // txlemetry?.callMethod('init'.toJS, config.projectToken.toJS, jsOptions);

    final ph = txlemetry;
    _config = config;
    _beforeSendCallbacks = config.beforeSend;

    // txlemetry-js is initialized by the host app, so a few config options never
    // reach it. Warn instead of silently ignoring them.
    if (!config.preloadFeatureFlags) {
      printIfDebug(
        'Warning: TxlemetryConfig.preloadFeatureFlags is not applied on Flutter web. '
        'txlemetry-js is initialized by your app, so set '
        'advanced_disable_feature_flags_on_first_load in your txlemetry.init({...}) call instead.',
      );
    }
    if (config.bootstrap != null) {
      printIfDebug(
        'Warning: TxlemetryConfig.bootstrap is not applied on Flutter web. '
        'Configure bootstrap in your txlemetry.init({...}) call instead.',
      );
    }

    WebCanvasMaskProvider(config).register();

    if (config.onFeatureFlags != null && ph != null) {
      final dartCallback = config.onFeatureFlags!;

      // JS SDK calls with: (flags: string[], variants: Record, context?: {errorsLoading})
      // We ignore the JS parameters and just invoke the void callback
      final jsCallback =
          (JSArray jsFlags, JSObject jsFlagVariants, [JSObject? jsContext]) {
        dartCallback();
      }.toJS;

      ph.onFeatureFlags(jsCallback);
    }
  }

  @override
  Future<void> identify({
    required String userId,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    return handleWebMethodCall(
      MethodCall('identify', {
        'userId': userId,
        if (userProperties != null) 'userProperties': userProperties,
        if (userPropertiesSetOnce != null)
          'userPropertiesSetOnce': userPropertiesSetOnce,
      }),
    );
  }

  @override
  Future<void> setPersonProperties({
    Map<String, Object>? userPropertiesToSet,
    Map<String, Object>? userPropertiesToSetOnce,
  }) async {
    if ((userPropertiesToSet?.isEmpty ?? true) &&
        (userPropertiesToSetOnce?.isEmpty ?? true)) {
      return;
    }

    return handleWebMethodCall(
      MethodCall('setPersonProperties', {
        if (userPropertiesToSet != null)
          'userPropertiesToSet': userPropertiesToSet,
        if (userPropertiesToSetOnce != null)
          'userPropertiesToSetOnce': userPropertiesToSetOnce,
      }),
    );
  }

  @override
  Future<void> capture({
    required String eventName,
    Map<String, Object>? properties,
    Map<String, Object>? userProperties,
    Map<String, Object>? userPropertiesSetOnce,
  }) async {
    final processedEvent = await _runBeforeSend(
      eventName,
      properties,
      userProperties: userProperties,
      userPropertiesSetOnce: userPropertiesSetOnce,
    );
    if (processedEvent == null) {
      printIfDebug('[Txlemetry] Event dropped by beforeSend: $eventName');
      return;
    }

    final extracted = CaptureUtils.extractUserProperties(
      properties: processedEvent.properties,
      userProperties: processedEvent.userProperties,
      userPropertiesSetOnce: processedEvent.userPropertiesSetOnce,
    );

    final extractedProperties = extracted.properties;
    final extractedUserProperties = extracted.userProperties;
    final extractedUserPropertiesSetOnce = extracted.userPropertiesSetOnce;

    final normalizedProperties = extractedProperties != null
        ? PropertyNormalizer.normalize(extractedProperties)
        : null;
    final normalizedUserProperties = extractedUserProperties != null
        ? PropertyNormalizer.normalize(extractedUserProperties)
        : null;
    final normalizedUserPropertiesSetOnce =
        extractedUserPropertiesSetOnce != null
            ? PropertyNormalizer.normalize(extractedUserPropertiesSetOnce)
            : null;

    return handleWebMethodCall(
      MethodCall('capture', {
        'eventName': processedEvent.event,
        if (normalizedProperties != null) 'properties': normalizedProperties,
        if (normalizedUserProperties != null)
          'userProperties': normalizedUserProperties,
        if (normalizedUserPropertiesSetOnce != null)
          'userPropertiesSetOnce': normalizedUserPropertiesSetOnce,
      }),
    );
  }

  @override
  Future<void> captureLog({
    required String body,
    TxlemetryLogSeverity level = TxlemetryLogSeverity.info,
    Map<String, Object>? attributes,
    String? traceId,
    String? spanId,
    int? traceFlags,
  }) async {
    final normalizedAttributes =
        attributes != null ? PropertyNormalizer.normalize(attributes) : null;

    return handleWebMethodCall(
      MethodCall('captureLog', {
        'body': body,
        'level': level.name,
        if (normalizedAttributes != null) 'attributes': normalizedAttributes,
        if (traceId != null) 'traceId': traceId,
        if (spanId != null) 'spanId': spanId,
        // traceFlags 0 is meaningful (W3C sampled-false); only omit when null.
        if (traceFlags != null) 'traceFlags': traceFlags,
      }),
    );
  }

  @override
  Future<void> screen({
    required String screenName,
    Map<String, Object>? properties,
  }) async {
    // The screen name argument wins over a properties `$screen_name`.
    // beforeSend still runs after this and can change the name.
    final propsWithScreenName = <String, Object>{
      ...?properties,
      TxlemetryPropertyName.screenName: screenName,
    };

    final processedEvent = await _runBeforeSend(
      TxlemetryEventName.screen,
      propsWithScreenName,
    );
    if (processedEvent == null) {
      printIfDebug('[Txlemetry] Screen event dropped by beforeSend: $screenName');
      return;
    }

    if (processedEvent.event != TxlemetryEventName.screen) {
      await capture(
        eventName: processedEvent.event,
        properties: processedEvent.properties?.cast<String, Object>(),
      );
      return;
    }

    final finalScreenName =
        processedEvent.properties?[TxlemetryPropertyName.screenName] as String? ??
            screenName;
    processedEvent.properties?.remove(TxlemetryPropertyName.screenName);
    final remaining = processedEvent.properties;

    return handleWebMethodCall(
      MethodCall('screen', {
        'screenName': finalScreenName,
        if (remaining != null && remaining.isNotEmpty) 'properties': remaining,
      }),
    );
  }

  @override
  Future<void> alias({required String alias}) async {
    return handleWebMethodCall(MethodCall('alias', {'alias': alias}));
  }

  @override
  Future<String> getDistinctId() async {
    final result = await handleWebMethodCall(const MethodCall('distinctId'));
    return result as String? ?? '';
  }

  @override
  Future<void> reset() async {
    return handleWebMethodCall(const MethodCall('reset'));
  }

  @override
  Future<void> disable() async {
    return handleWebMethodCall(const MethodCall('disable'));
  }

  @override
  Future<void> enable() async {
    return handleWebMethodCall(const MethodCall('enable'));
  }

  @override
  Future<bool> isOptOut() async {
    final result = await handleWebMethodCall(const MethodCall('isOptOut'));
    return result as bool? ?? true;
  }

  @override
  Future<void> debug(bool enabled) async {
    return handleWebMethodCall(MethodCall('debug', {'debug': enabled}));
  }

  @override
  Future<void> register(String key, Object value) async {
    return handleWebMethodCall(
      MethodCall('register', {'key': key, 'value': value}),
    );
  }

  @override
  Future<void> unregister(String key) async {
    return handleWebMethodCall(MethodCall('unregister', {'key': key}));
  }

  @override
  Future<bool> isFeatureEnabled(String key) async {
    final result = await handleWebMethodCall(
      MethodCall('isFeatureEnabled', {'key': key}),
    );
    return result as bool? ?? false;
  }

  @override
  Future<void> reloadFeatureFlags() async {
    return handleWebMethodCall(const MethodCall('reloadFeatureFlags'));
  }

  @override
  Future<void> setPersonPropertiesForFlags(
    Map<String, Object> userProperties,
  ) async {
    return handleWebMethodCall(
      MethodCall('setPersonPropertiesForFlags', {
        'userProperties': userProperties,
      }),
    );
  }

  @override
  Future<void> resetPersonPropertiesForFlags() async {
    return handleWebMethodCall(
      const MethodCall('resetPersonPropertiesForFlags'),
    );
  }

  @override
  Future<void> setGroupPropertiesForFlags(
    String groupType,
    Map<String, Object> groupProperties,
  ) async {
    return handleWebMethodCall(
      MethodCall('setGroupPropertiesForFlags', {
        'groupType': groupType,
        'groupProperties': groupProperties,
      }),
    );
  }

  @override
  Future<void> resetGroupPropertiesForFlags({String? groupType}) async {
    return handleWebMethodCall(
      MethodCall('resetGroupPropertiesForFlags', {
        if (groupType != null) 'groupType': groupType,
      }),
    );
  }

  @override
  Future<void> group({
    required String groupType,
    required String groupKey,
    Map<String, Object>? groupProperties,
  }) async {
    return handleWebMethodCall(
      MethodCall('group', {
        'groupType': groupType,
        'groupKey': groupKey,
        if (groupProperties != null) 'groupProperties': groupProperties,
      }),
    );
  }

  @override
  Future<Object?> getFeatureFlag({required String key}) async {
    return handleWebMethodCall(MethodCall('getFeatureFlag', {'key': key}));
  }

  @override
  Future<Object?> getFeatureFlagPayload({required String key}) async {
    return handleWebMethodCall(
      MethodCall('getFeatureFlagPayload', {'key': key}),
    );
  }

  @override
  Future<TxlemetryFeatureFlagResult?> getFeatureFlagResult({
    required String key,
    bool sendEvent = true,
  }) async {
    final result = await handleWebMethodCall(
      MethodCall('getFeatureFlagResult', {'key': key, 'sendEvent': sendEvent}),
    );

    // Web SDK returns: { key, enabled, variant, payload }
    return TxlemetryFeatureFlagResult.fromMap(result, key);
  }

  @override
  Future<void> flush() async {
    return handleWebMethodCall(const MethodCall('flush'));
  }

  @override
  Future<void> close() async {
    return handleWebMethodCall(const MethodCall('close'));
  }

  @override
  Future<String?> getSessionId() async {
    final result = await handleWebMethodCall(const MethodCall('getSessionId'));
    return result as String?;
  }

  @override
  Future<void> openUrl(String url) async {
    // Not supported on web
  }

  @override
  Future<void> showSurvey(Map<String, dynamic> survey) async {
    // Not supported on web - surveys handled by txlemetry-js
  }

  @override
  Future<void> registerPushNotificationToken(
    String deviceToken, {
    String? appId,
  }) async {
    // Not supported on web - txlemetry-js has no push subscription API
  }

  @override
  Future<void> unregisterPushNotificationToken() async {
    // Not supported on web - txlemetry-js has no push subscription API
  }

  @override
  Future<void> capturePushNotificationOpened({
    String? title,
    String? subtitle,
    String? body,
    Map<String, Object?>? payload,
    String? action,
  }) async {
    // Not supported on web - txlemetry-js has no push subscription API
  }

  @override
  Future<void> captureException({
    required Object error,
    StackTrace? stackTrace,
    Map<String, Object>? properties,
  }) async {
    try {
      final exceptionData = DartExceptionProcessor.processException(
        error: error,
        stackTrace: stackTrace,
        properties: properties,
        inAppIncludes: _config?.errorTrackingConfig.inAppIncludes,
        inAppExcludes: _config?.errorTrackingConfig.inAppExcludes,
        inAppByDefault: _config?.errorTrackingConfig.inAppByDefault ?? true,
      );

      final processedEvent = await _runBeforeSend(
        TxlemetryEventName.exception,
        exceptionData.cast<String, Object>(),
      );
      if (processedEvent == null) {
        printIfDebug(
          '[Txlemetry] Exception event dropped by beforeSend: ${error.runtimeType}',
        );
        return;
      }

      if (processedEvent.event != TxlemetryEventName.exception) {
        await capture(
          eventName: processedEvent.event,
          properties: processedEvent.properties?.cast<String, Object>(),
        );
        return;
      }

      final normalizedData = PropertyNormalizer.normalize(
        processedEvent.properties?.cast<String, Object>() ?? <String, Object>{},
      );

      return await handleWebMethodCall(
        MethodCall('captureException', {'properties': normalizedData}),
      );
    } catch (error) {
      printIfDebug('Exception in captureException: $error');
    }
  }

  @override
  Future<void> startSessionRecording({bool resumeCurrent = true}) async {
    return handleWebMethodCall(
      MethodCall('startSessionRecording', {'resumeCurrent': resumeCurrent}),
    );
  }

  @override
  Future<void> stopSessionRecording() async {
    return handleWebMethodCall(const MethodCall('stopSessionRecording'));
  }

  @override
  Future<bool> isSessionReplayActive() async {
    final result = await handleWebMethodCall(
      const MethodCall('isSessionReplayActive'),
    );
    return result as bool? ?? false;
  }

  @override
  Future<void> addExceptionStep(
    String message, {
    Map<String, Object>? properties,
  }) async {
    final normalizedProperties =
        properties != null ? PropertyNormalizer.normalize(properties) : null;

    return handleWebMethodCall(
      MethodCall('addExceptionStep', {
        'message': message,
        if (normalizedProperties != null) 'properties': normalizedProperties,
      }),
    );
  }
}
