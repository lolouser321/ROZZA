import Flutter

final class PlaybackChannelPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let controller = NativePlaybackController.shared

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PlaybackChannelPlugin()
    let commands = FlutterMethodChannel(name: "com.rozza.playback/commands", binaryMessenger: registrar.messenger())
    let events = FlutterEventChannel(name: "com.rozza.playback/events", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: commands)
    events.setStreamHandler(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "play": Self.controller.play(); result(nil)
    case "pause": Self.controller.pause(); result(nil)
    case "next": Self.controller.next(); result(nil)
    case "previous": Self.controller.previous(); result(nil)
    case "seek":
      let position = (arguments?["positionMs"] as? NSNumber)?.intValue ?? 0
      Self.controller.seek(positionMs: position)
      result(nil)
    case "loadTrack":
      guard let track = arguments?["track"] as? [String: Any] else {
        result(FlutterError(code: "invalid-track", message: "loadTrack requires a track map", details: nil)); return
      }
      Self.controller.loadTrack(track, autoplay: arguments?["autoplay"] as? Bool ?? false)
      result(nil)
    case "setQueue":
      let tracks = arguments?["tracks"] as? [[String: Any]] ?? []
      let startIndex = (arguments?["startIndex"] as? NSNumber)?.intValue ?? 0
      Self.controller.setQueue(tracks, startIndex: startIndex)
      result(nil)
    case "getPlaybackState": result(Self.controller.snapshot())
    default: result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    Self.controller.eventHandler = events
    events(["event": "playbackStateChanged", "state": Self.controller.snapshot()])
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    Self.controller.eventHandler = nil
    return nil
  }
}
