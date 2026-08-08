import Foundation

/// Structured diagnostics for physical-device testing — Lock Screen, Control
/// Center, background/foreground transitions. Mirrors the JS-side `DEBUG`
/// flag in rozza2.html; the two are independent (this gates native NSLog
/// output, the JS flag gates console.log + the dev diagnostics panel), but
/// both should flip to `false` together before shipping.
enum DebugConfig {
    static let isEnabled = true
}
