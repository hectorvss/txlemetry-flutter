import 'package:flutter/material.dart';
import 'package:txlemetry_flutter/txlemetry_flutter.dart';
import 'package:txlemetry_flutter/src/replay/element_parsers/element_data.dart';
import 'package:txlemetry_flutter/src/replay/element_parsers/element_parser.dart';
import 'package:txlemetry_flutter/src/replay/element_parsers/element_parser_factory.dart';
import 'package:txlemetry_flutter/src/replay/element_parsers/element_parsers_const.dart';
import 'package:txlemetry_flutter/src/replay/element_parsers/element_data_factory.dart';
import 'package:txlemetry_flutter/src/replay/element_parsers/element_object_parser.dart';
import 'package:txlemetry_flutter/src/replay/element_parsers/root_element_provider.dart';
import 'package:txlemetry_flutter/src/replay/mask/widget_elements_decipher.dart';
import 'package:txlemetry_flutter/src/util/logging.dart';

class TxlemetryMaskController {
  Map<String, ElementParser> parsers;

  final GlobalKey containerKey = GlobalKey();

  final WidgetElementsDecipher _widgetScraper;

  TxlemetryMaskController._privateConstructor(TxlemetrySessionReplayConfig? config)
      : parsers = _buildParsers(config),
        _widgetScraper = WidgetElementsDecipher(
          elementDataFactory: ElementDataFactory(),
          elementObjectParser: ElementObjectParser(),
          rootElementProvider: RootElementProvider(),
        );

  static Map<String, ElementParser> _buildParsers(
    TxlemetrySessionReplayConfig? config,
  ) {
    return ElementParsersConst(
      DefaultElementParserFactory(),
      config,
    ).parsersMap;
  }

  /// Rebuilds the parser map for [config]. The singleton captures the config
  /// present at first access, which a later `setup()` with different masking
  /// flags would otherwise never update.
  void refreshParsers(TxlemetrySessionReplayConfig? config) {
    parsers = _buildParsers(config);
  }

  static final TxlemetryMaskController instance =
      TxlemetryMaskController._privateConstructor(
    Txlemetry().config?.sessionReplayConfig,
  );

  /// Extracts a flattened list of [ElementData] objects for every element in
  /// the widget tree that matched a masking rule, at any depth.
  List<ElementData>? getCurrentWidgetsElements() {
    final context = containerKey.currentContext;

    if (context == null) {
      printIfDebug('Error: containerKey.currentContext is null.');
      return null;
    }

    try {
      final widgetElementsTree = _widgetScraper.parseRenderTree(context);

      if (widgetElementsTree == null) {
        printIfDebug('Error: widgetElementsTree is null after parsing.');
        return null;
      }

      return widgetElementsTree.extractRects();
    } catch (e) {
      printIfDebug(
        'Error during render tree parsing or rectangle extraction: $e',
      );
      return null;
    }
  }

  /// Single-walk variant used by web canvas masking: one [parseRenderTree]
  /// producing both the explicit-mask set and (optionally) the full text/image
  /// set, instead of two separate walks. Returns null when the tree can't be
  /// walked (no [TxlemetryWidget] mounted, or parsing failed) so callers can
  /// fail closed.
  List<ElementData>? getMaskElements({required bool includeAllWidgets}) {
    final context = containerKey.currentContext;

    if (context == null) {
      printIfDebug('Error: containerKey.currentContext is null.');
      return null;
    }

    try {
      final widgetElementsTree = _widgetScraper.parseRenderTree(context);

      if (widgetElementsTree == null) {
        printIfDebug('Error: widgetElementsTree is null after parsing.');
        return null;
      }

      return [
        ...widgetElementsTree.extractMaskWidgetRects(),
        if (includeAllWidgets) ...widgetElementsTree.extractRects(),
      ];
    } catch (e) {
      printIfDebug(
        'Error during render tree parsing or rectangle extraction: $e',
      );
      return null;
    }
  }

  List<ElementData>? getTxlemetryWidgetWrapperElements() {
    final context = containerKey.currentContext;

    if (context == null) {
      printIfDebug('Error: containerKey.currentContext is null.');
      return null;
    }

    try {
      final widgetElementsTree = _widgetScraper.parseRenderTree(context);

      if (widgetElementsTree == null) {
        printIfDebug('Error: widgetElementsTree is null after parsing.');
        return null;
      }

      return widgetElementsTree.extractMaskWidgetRects();
    } catch (e) {
      printIfDebug(
        'Error during render tree parsing or rectangle extraction: $e',
      );
      return null;
    }
  }
}
