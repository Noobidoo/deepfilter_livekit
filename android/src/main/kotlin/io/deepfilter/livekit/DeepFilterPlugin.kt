package io.deepfilter.livekit

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DeepFilterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var nativeState: Long = 0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "io.deepfilter.livekit")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                result.success(true)
            }
            "init" -> {
                try {
                    val modelPath = call.argument<String>("modelPath") ?: ""
                    val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                    if (nativeState != 0L) {
                        nativeDestroy(nativeState)
                    }
                    nativeState = nativeInit(modelPath, sampleRate)
                    result.success("ok")
                } catch (e: Exception) {
                    result.error("INIT_FAILED", e.message, null)
                }
            }
            "processFrame" -> {
                try {
                    val input = call.argument<ByteArray>("input") ?: throw IllegalArgumentException("input required")
                    val output = ByteArray(input.size)
                    val ret = nativeProcessFrame(nativeState, input, output)
                    result.success(mapOf("output" to output, "ret" to ret))
                } catch (e: Exception) {
                    result.error("PROCESS_FAILED", e.message, null)
                }
            }
            "dispose" -> {
                if (nativeState != 0L) {
                    nativeDestroy(nativeState)
                    nativeState = 0
                }
                result.success(null)
            }
            "getFrameSize" -> {
                if (nativeState == 0L) {
                    result.error("NOT_INIT", "Not initialized", null)
                } else {
                    result.success(nativeFrameSize(nativeState))
                }
            }
            else -> result.notImplemented()
        }
    }

    private external fun nativeInit(modelPath: String, sampleRate: Int): Long
    private external fun nativeDestroy(state: Long)
    private external fun nativeProcessFrame(state: Long, input: ByteArray, output: ByteArray): Int
    private external fun nativeFrameSize(state: Long): Int

    companion object {
        init {
            System.loadLibrary("deep_filter_jni")
        }
    }
}
