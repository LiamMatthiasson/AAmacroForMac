import Foundation
import CoreGraphics
import CoreText

/// Loads Vision's text-recognition models in the background as soon as the app opens.
///
/// On macOS 27 the *accurate* text model is compiled the first time it is used — 68 seconds on
/// this Mac (tools/ocrbench.swift). macOS keeps the compiled copy, but can throw it away after an
/// OS update, a reboot, or when disk space runs low. Every text read in the macro runs on the main
/// thread, so a cold first read froze the whole app for over a minute. Force-quitting it — the
/// reasonable thing to do with a frozen app — aborted the compile, so nothing was cached and the
/// next launch froze again.
///
/// Doing it here, off the main thread, means that minute passes in the background while the window
/// stays usable, and Start waits for it instead of freezing.
enum OCRWarmup {
    @MainActor private(set) static var ready = false
    @MainActor private static var started = false

    @MainActor static func begin(_ log: @escaping @MainActor @Sendable (String) -> Void) {
        guard !started else { return }
        started = true
        Task.detached(priority: .userInitiated) {
            let t0 = Date()
            // Real text, so the recognizer itself runs: on a blank image Vision can stop at the
            // text detector and never load the model this is here to load. Both modes, through
            // OCR.read, so it warms exactly the configuration the macro uses.
            if let img = sample() {
                _ = try? OCR.read(img, fast: true)
                _ = try? OCR.read(img, fast: false)
            }
            let secs = Date().timeIntervalSince(t0)
            await MainActor.run {
                ready = true
                if secs > 3 {
                    log(String(format: "Text recognition loaded in the background (%.0fs). macOS rebuilds it after updates or when disk space runs low.", secs))
                }
            }
        }
    }

    /// "Play 12345" in black on white, drawn with Core Text (safe off the main thread).
    private static func sample() -> CGImage? {
        let w = 640, h = 160
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 56, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font,
                                      kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)]
        guard let text = CFAttributedStringCreate(nil, "Play 12345" as CFString, attrs as CFDictionary) else { return nil }
        ctx.textPosition = CGPoint(x: 24, y: 52)
        CTLineDraw(CTLineCreateWithAttributedString(text), ctx)
        return ctx.makeImage()
    }
}
