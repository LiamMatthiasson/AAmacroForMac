import Foundation
import Vision
import AppKit

// Times Vision text recognition the way AAMacro uses it, to find out why one full-frame
// read takes ~65s on macOS 27 when it used to take about a second.
// Lives outside Sources/ so it is never compiled into the app.

let args = CommandLine.arguments
guard args.count > 1,
      let img = NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: ocrbench <image.png>")
    exit(1)
}
print("image: \(img.width)x\(img.height)")
print("supported revisions: \(VNRecognizeTextRequest.supportedRevisions.sorted())")
print("default revision:    \(VNRecognizeTextRequest.currentRevision)")
print("")

func run(_ name: String, warmUp: Bool = false, _ setup: (VNRecognizeTextRequest) -> Void) {
    let r = VNRecognizeTextRequest()
    r.usesLanguageCorrection = false
    setup(r)
    let t0 = Date()
    do {
        try VNImageRequestHandler(cgImage: img).perform([r])
        let secs = Date().timeIntervalSince(t0)
        if warmUp { print("(warm-up: \(String(format: "%.2f", secs))s)\n"); return }
        let label = name.padding(toLength: 30, withPad: " ", startingAt: 0)
        print("\(label) \(String(format: "%7.2f", secs))s   \(r.results?.count ?? 0) lines")
    } catch {
        print("\(name): FAILED — \(error.localizedDescription)")
    }
}

run("warm-up", warmUp: true) { $0.recognitionLevel = .fast }

// The FIRST accurate call uses the app's exact settings (English, revision 3). If this one row is
// slow and everything after it is fast, the cost is the model compiling on first use — not any
// setting. The first version of this file ran "defaults" first and so couldn't tell the two apart.
let t0 = Date()
run("accurate, app settings (FIRST)") { $0.recognitionLevel = .accurate; $0.recognitionLanguages = ["en-US"]; $0.revision = VNRecognizeTextRequestRevision3 }
let firstAccurate = Date().timeIntervalSince(t0)
print(firstAccurate > 10
      ? "\n  -> first accurate read was slow even with the app's settings: model compiling on first use (cold cache)\n"
      : "\n  -> first accurate read was fast: the model was already compiled (warm cache) — rows below can't tell us anything about cold start\n")

run("accurate, defaults")            { $0.recognitionLevel = .accurate }
run("fast, defaults")                { $0.recognitionLevel = .fast }
run("accurate, en-US only")          { $0.recognitionLevel = .accurate; $0.recognitionLanguages = ["en-US"] }
run("fast, en-US only")              { $0.recognitionLevel = .fast;     $0.recognitionLanguages = ["en-US"] }
for rev in VNRecognizeTextRequest.supportedRevisions.sorted() {
    run("accurate, revision \(rev)")  { $0.recognitionLevel = .accurate; $0.revision = rev }
    run("fast, revision \(rev)")      { $0.recognitionLevel = .fast;     $0.revision = rev }
}
