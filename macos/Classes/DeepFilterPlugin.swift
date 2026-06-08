import Flutter
import Cocoa

public class DeepFilterPlugin: NSObject, FlutterPlugin {
    private var state: OpaquePointer?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "io.deepfilter.livekit", binaryMessenger: registrar.messenger)
        let instance = DeepFilterPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(true)
        case "init":
            guard let args = call.arguments as? [String: Any],
                  let sampleRate = args["sampleRate"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
                return
            }
            let modelPath = args["modelPath"] as? String ?? ""
            if state != nil {
                df_destroy(state)
            }
            state = modelPath.isEmpty
                ? df_init(nil, Int32(sampleRate))
                : df_init((modelPath as NSString).utf8String, Int32(sampleRate))
            if state == nil {
                result(FlutterError(code: "INIT_FAILED", message: "df_init returned nil", details: nil))
            } else {
                result("ok")
            }
        case "processFrame":
            guard let args = call.arguments as? [String: Any],
                  let inputData = args["input"] as? FlutterStandardTypedData,
                  let s = state else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
                return
            }
            let inputCount = inputData.data.count / MemoryLayout<Float>.size
            var outputData = Data(count: inputData.data.count)
            let ret = inputData.data.withUnsafeBytes { (inPtr: UnsafeRawBufferPointer) -> Int32 in
                outputData.withUnsafeMutableBytes { (outPtr: UnsafeMutableRawBufferPointer) in
                    let inFloats = inPtr.bindMemory(to: Float.self)
                    let outFloats = outPtr.bindMemory(to: Float.self)
                    return df_process_frame(s, inFloats.baseAddress, outFloats.baseAddress, Int32(inputCount))
                }
            }
            result([
                "output": FlutterStandardTypedData(bytes: outputData),
                "ret": Int(ret),
            ])
        case "dispose":
            if let s = state {
                df_destroy(s)
                state = nil
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
