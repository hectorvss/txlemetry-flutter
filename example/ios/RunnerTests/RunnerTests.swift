import Flutter
import Txlemetry
@testable import txlemetry_flutter
import UIKit
import XCTest

// Unit tests of the Swift portion of this plugin's implementation.
//
// Mirrors the Android `TxlemetryFlutterPluginTest`. Run from the example app's
// iOS test target.
//
// See https://developer.apple.com/documentation/xctest for more information
// about using XCTest.

class RunnerTests: XCTestCase {
    func testCaptureLogRoutesToCaptureLogAndSucceeds() {
        var records: [TxlemetryLogRecord] = []
        let config = TxlemetryConfig(projectToken: "log-channel-test", host: "http://127.0.0.1:1")
        config.preloadFeatureFlags = false
        config.captureApplicationLifecycleEvents = false
        config.setBeforeSend { _ in nil }
        config.logs.setBeforeSend { record in
            records.append(record)
            return nil
        }
        TxlemetrySDK.shared.close()
        TxlemetrySDK.shared.setup(config)
        defer { TxlemetrySDK.shared.close() }
        let plugin = TxlemetryFlutterPlugin()

        let arguments: [String: Any] = [
            "body": "checkout completed",
            "level": "warn",
            "attributes": ["order_id": "ord_789"],
            "traceId": "4bf92f3577b34da6a3ce929d0e0e4736",
            "spanId": "00f067aa0ba902b7",
            "traceFlags": 1,
        ]
        let call = FlutterMethodCall(methodName: "captureLog", arguments: arguments)

        var resultCalled = false
        var resultValue: Any?
        plugin.handle(call) { value in
            resultCalled = true
            resultValue = value
        }

        XCTAssertTrue(resultCalled)
        XCTAssertNil(resultValue)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.body, "checkout completed")
        XCTAssertEqual(records.first?.level, .warn)
        XCTAssertEqual(records.first?.attributes["order_id"] as? String, "ord_789")
        XCTAssertEqual(records.first?.traceId, "4bf92f3577b34da6a3ce929d0e0e4736")
        XCTAssertEqual(records.first?.spanId, "00f067aa0ba902b7")
        XCTAssertEqual(records.first?.traceFlags, 1)

        plugin.handle(FlutterMethodCall(methodName: "captureLog", arguments: ["body": "default", "traceFlags": 0])) { _ in }
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.last?.body, "default")
        XCTAssertEqual(records.last?.level, .info)
        XCTAssertEqual(records.last?.traceFlags, 0)
        XCTAssertNil(records.last?.traceId)
        XCTAssertNil(records.last?.spanId)
    }

    func testFlutterVersionAddedOnlyToInstallAndUpdateEvents() throws {
        var flutterVersions: [String: String] = [:]
        let config = TxlemetryConfig(projectToken: "flutter-version-test", host: "http://127.0.0.1:1")
        config.preloadFeatureFlags = false
        config.captureApplicationLifecycleEvents = false
        config.setBeforeSend(
            try XCTUnwrap(TxlemetryFlutterPlugin.flutterVersionBeforeSend(["flutterVersion": "3.35.0"])),
            { event in
                flutterVersions[event.event] = event.properties["$flutter_version"] as? String ?? "none"
                return nil
            }
        )
        TxlemetrySDK.shared.close()
        TxlemetrySDK.shared.setup(config)
        defer { TxlemetrySDK.shared.close() }

        for event in ["Application Installed", "Application Updated", "Application Opened", "custom"] {
            TxlemetrySDK.shared.capture(event)
        }

        XCTAssertEqual(flutterVersions, [
            "Application Installed": "3.35.0",
            "Application Updated": "3.35.0",
            "Application Opened": "none",
            "custom": "none",
        ])
        XCTAssertNil(TxlemetryFlutterPlugin.flutterVersionBeforeSend([:]))
    }

    func testCaptureLogMissingBodyReturnsError() {
        let plugin = TxlemetryFlutterPlugin()

        let call = FlutterMethodCall(methodName: "captureLog", arguments: [String: Any]())

        var resultValue: Any?
        plugin.handle(call) { value in
            resultValue = value
        }

        let error = resultValue as? FlutterError
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, "TxlemetryFlutterException")
    }

    func testSendFullSnapshotReportsUndecodableImageAsError() {
        let reply = sendFullSnapshot(Data([0x00, 0x01, 0x02]))

        let error = reply as? FlutterError
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, "TxlemetryFlutterException")
    }

    func testSendFullSnapshotSucceedsForDecodableImage() {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }

        XCTAssertNil(sendFullSnapshot(png))
    }

    private func sendFullSnapshot(_ imageBytes: Data) -> Any? {
        let call = FlutterMethodCall(
            methodName: "sendFullSnapshot",
            arguments: ["imageBytes": FlutterStandardTypedData(bytes: imageBytes), "id": 1, "x": 0, "y": 0]
        )
        let replied = expectation(description: "reply")
        var reply: Any?
        TxlemetryFlutterPlugin().handle(call) { value in
            reply = value
            replied.fulfill()
        }
        wait(for: [replied], timeout: 5)
        return reply
    }
}
