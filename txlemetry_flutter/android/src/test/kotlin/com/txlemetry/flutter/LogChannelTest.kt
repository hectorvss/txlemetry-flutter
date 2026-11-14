package com.txlemetry.flutter

import com.txlemetry.Txlemetry
import com.txlemetry.android.TxlemetryAndroid
import com.txlemetry.android.TxlemetryAndroidConfig
import com.txlemetry.logs.TxlemetryLogRecord
import com.txlemetry.logs.TxlemetryLogSeverity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertNull

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
class LogChannelTest {
    @Test
    fun forwardsLogFieldsAndDefaultsToNativeSdk() {
        val records = mutableListOf<TxlemetryLogRecord>()
        val config =
            TxlemetryAndroidConfig("log-channel-test", "http://127.0.0.1:1").apply {
                preloadFeatureFlags = false
                captureApplicationLifecycleEvents = false
                captureDeepLinks = false
                logs.addBeforeSend { record ->
                    records.add(record)
                    null
                }
            }
        TxlemetryAndroid.setup(RuntimeEnvironment.getApplication(), config)
        try {
            val plugin = TxlemetryFlutterPlugin()
            for (flags in listOf(0, 1)) {
                val result = Mockito.mock(MethodChannel.Result::class.java)
                plugin.onMethodCall(
                    MethodCall(
                        "captureLog",
                        mapOf(
                            "body" to "checkout completed",
                            "level" to "warn",
                            "attributes" to mapOf("order_id" to "ord_789"),
                            "traceId" to "4bf92f3577b34da6a3ce929d0e0e4736",
                            "spanId" to "00f067aa0ba902b7",
                            "traceFlags" to flags,
                        ),
                    ),
                    result,
                )
                Mockito.verify(result).success(null)
            }
            plugin.onMethodCall(
                MethodCall("captureLog", mapOf("body" to "default")),
                Mockito.mock(MethodChannel.Result::class.java),
            )
            assertEquals(3, records.size)
            for ((flags, record) in records.take(2).withIndex()) {
                assertEquals("checkout completed", record.body)
                assertEquals(TxlemetryLogSeverity.WARN, record.level)
                assertEquals(mapOf("order_id" to "ord_789"), record.attributes)
                assertEquals("4bf92f3577b34da6a3ce929d0e0e4736", record.traceId)
                assertEquals("00f067aa0ba902b7", record.spanId)
                assertEquals(flags, record.traceFlags)
            }
            assertEquals("default", records.last().body)
            assertEquals(TxlemetryLogSeverity.INFO, records.last().level)
            assertNull(records.last().traceId)
            assertNull(records.last().spanId)
            assertNull(records.last().traceFlags)
        } finally {
            Txlemetry.close()
        }
    }
}
