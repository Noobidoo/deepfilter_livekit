package io.deepfilter.livekit

import android.content.Context
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import kotlin.concurrent.Volatile

class DeepFilterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    @Volatile private var nativeState: Long = 0
    @Volatile private var apmAdapter: AudioProcessingAdapter? = null
    private var apmProcessor: AudioProcessingAdapter.ExternalAudioFrameProcessing? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "io.deepfilter.livekit")
        channel.setMethodCallHandler(this)
    }

    private fun attachApmHook() {
        try {
            val plugin = FlutterWebRTCPlugin.sharedSingleton ?: run {
                Log.w(TAG, "APM hook: FlutterWebRTCPlugin not available")
                return
            }
            val controller = plugin.audioProcessingController ?: run {
                Log.w(TAG, "APM hook: audioProcessingController not available")
                return
            }
            val adapter = controller.capturePostProcessing
            apmAdapter = adapter

            val processor = object : AudioProcessingAdapter.ExternalAudioFrameProcessing {
                private var dfFrameSize = 0

                override fun initialize(sampleRateHz: Int, numChannels: Int) {
                    Log.i(TAG, "APM init: rate=$sampleRateHz ch=$numChannels")
                }

                override fun reset(newRate: Int) {
                    Log.i(TAG, "APM reset: rate=$newRate")
                }

                override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
                    val state = nativeState
                    if (state == 0L) return

                    if (dfFrameSize <= 0) {
                        dfFrameSize = nativeFrameSize(state).toInt()
                        if (dfFrameSize <= 0) return
                    }

                    val pos = buffer.position()
                    val len = buffer.remaining()
                    val frameBytes = dfFrameSize * 4
                    if (len < frameBytes) return

                    val framesToProcess = len / frameBytes
                    val totalBytes = framesToProcess * frameBytes
                    val input = ByteArray(totalBytes)
                    val output = ByteArray(totalBytes)
                    buffer.get(input)
                    try {
                        var inOff = 0
                        var outOff = 0
                        val frameInput = ByteArray(frameBytes)
                        val frameOutput = ByteArray(frameBytes)
                        for (i in 0 until framesToProcess) {
                            System.arraycopy(input, inOff, frameInput, 0, frameBytes)
                            nativeProcessFrame(state, frameInput, frameOutput)
                            System.arraycopy(frameOutput, 0, output, outOff, frameBytes)
                            inOff += frameBytes
                            outOff += frameBytes
                        }
                        buffer.position(pos)
                        buffer.put(output)
                    } catch (e: Exception) {
                        Log.w(TAG, "APM process error", e)
                        buffer.position(pos)
                        buffer.put(input)
                    }
                }
            }
            apmProcessor = processor
            adapter.addProcessor(processor)
            Log.i(TAG, "APM hook attached")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to attach APM hook", e)
        }
    }

    private fun detachApmHook() {
        val proc = apmProcessor
        val adapter = apmAdapter
        if (proc != null && adapter != null) {
            adapter.removeProcessor(proc)
            Log.i(TAG, "APM hook detached")
        }
        apmProcessor = null
        apmAdapter = null
    }

    private fun resolveModelPath(modelPath: String): String {
        if (modelPath.isNotEmpty()) return modelPath
        val cached = File(context.cacheDir, "deepfilter/DeepFilterNet3_onnx.tar.gz")
        if (cached.exists()) {
            Log.i(TAG, "resolveModelPath: using cached $cached")
            return cached.absolutePath
        }
        try {
            context.assets.open(
                "flutter_assets/packages/deepfilter_livekit/assets/models/DeepFilterNet3_onnx.tar.gz"
            ).use { input ->
                cached.parentFile!!.mkdirs()
                cached.outputStream().use { output -> input.copyTo(output) }
            }
            Log.i(TAG, "resolveModelPath: extracted to $cached")
            return cached.absolutePath
        } catch (e: Exception) {
            Log.w(TAG, "resolveModelPath: failed to extract bundled model", e)
            return ""
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                result.success(nativeLoaded)
            }
            "init" -> {
                try {
                    checkAvailable()
                    val sampleRate = call.argument<Int>("sampleRate") ?: 48000
                    val modelPath = resolveModelPath(call.argument<String>("modelPath") ?: "")
                    if (modelPath.isEmpty()) {
                        result.error("INIT_FAILED", "No model path and bundled asset not found", null)
                        return
                    }
                    if (nativeState != 0L) {
                        nativeDestroy(nativeState)
                    }
                    Log.i(TAG, "calling nativeInit with path=$modelPath")
                    nativeState = nativeInit(modelPath, sampleRate)
                    Log.i(TAG, "nativeInit returned state=$nativeState")
                    if (nativeState == 0L) {
                        result.error("INIT_FAILED", "Model init returned null", null)
                    } else {
                        result.success("ok")
                    }
                } catch (e: Throwable) {
                    result.error("INIT_FAILED", e.message, null)
                }
            }
            "processFrame" -> {
                try {
                    checkAvailable()
                    val input = call.argument<ByteArray>("input") ?: throw IllegalArgumentException("input required")
                    val output = ByteArray(input.size)
                    val ret = nativeProcessFrame(nativeState, input, output)
                    result.success(mapOf("output" to output, "ret" to ret))
                } catch (e: Throwable) {
                    result.error("PROCESS_FAILED", e.message, null)
                }
            }
            "dispose" -> {
                try {
                    if (nativeState != 0L) {
                        nativeDestroy(nativeState)
                        nativeState = 0
                    }
                    result.success(null)
                } catch (e: Throwable) {
                    result.error("DISPOSE_FAILED", e.message, null)
                }
            }
            "attachApmHook" -> {
                attachApmHook()
                result.success(apmProcessor != null)
            }
            "setApmEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                Log.i(TAG, "setApmEnabled: $enabled")
                if (enabled) {
                    if (apmProcessor == null) attachApmHook()
                } else {
                    detachApmHook()
                }
                result.success(null)
            }
            "getFrameSize" -> {
                try {
                    checkAvailable()
                    if (nativeState == 0L) {
                        result.error("NOT_INIT", "Not initialized", null)
                    } else {
                        result.success(nativeFrameSize(nativeState))
                    }
                } catch (e: Throwable) {
                    result.error("FRAME_SIZE_FAILED", e.message, null)
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
        private const val TAG = "DeepFilterPlugin"
        var nativeLoaded = false
            private set

        init {
            try {
                System.loadLibrary("deep_filter_jni")
                nativeLoaded = true
            } catch (e: UnsatisfiedLinkError) {
                nativeLoaded = false
            }
        }
    }

    private fun checkAvailable() {
        if (!nativeLoaded) throw UnsatisfiedLinkError("Native library not loaded")
    }
}
