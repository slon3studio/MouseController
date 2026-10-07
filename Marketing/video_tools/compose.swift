import AVFoundation
import AppKit
import QuartzCore

// Cuts a simulator recording into the promo reel.
// Usage: compose <raw.mov> <layers folder> <output.mp4>
// Segment times below are for the recording made on 2026-10-06; a new
// recording needs new times (find them with frames.swift).

let args = CommandLine.arguments
let rawPath = args[1]
let layersPath = args[2]
let outputPath = args[3]

let renderSize = CGSize(width: 1080, height: 1920)
let screenRect = CGRect(x: 222, y: 450, width: 636, height: 1383)   // matches layers.py
let endCardDuration = 2.5
let fade = 0.18

// (source start, source end, caption index)
let segments: [(Double, Double, Int)] = [
    (10.5, 15.5, 0),      // radar searching, then finds the Mac
    (29.75, 31.75, 1),    // pairing sheet slides up
    (37.0, 39.0, 1),      // code entered
    (47.5, 50.0, 1),      // pair, trackpad appears
    (66.25, 69.25, 2),    // one-finger move, two-finger scroll
    (92.75, 96.75, 3),    // volume slider, media controls
    (97.25, 100.75, 4),   // keys panel, typing
    (129.0, 131.25, 5),   // settings sheet
    (132.0, 135.5, 6),    // back to the trackpad
]

func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

let source = AVURLAsset(url: URL(fileURLWithPath: rawPath))
let sourceTrack = source.tracks(withMediaType: .video)[0]

let composition = AVMutableComposition()
let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!

var cursor = 0.0
var captionRanges: [Int: (Double, Double)] = [:]

for (start, end, caption) in segments {
    try! track.insertTimeRange(CMTimeRange(start: time(start), end: time(end)), of: sourceTrack, at: time(cursor))
    let range = captionRanges[caption] ?? (cursor, cursor)
    captionRanges[caption] = (range.0, cursor + (end - start))
    cursor += end - start
}

let videoEnd = cursor
let total = videoEnd + endCardDuration
// Export drops trailing empty time, so the end card sits over real (hidden)
// footage instead.
try! track.insertTimeRange(
    CMTimeRange(start: time(15.5), duration: time(endCardDuration)), of: sourceTrack, at: time(videoEnd)
)

// Video into the phone's screen area. Layer instruction transforms use a
// top-left origin in pixels.
let scale = screenRect.width / sourceTrack.naturalSize.width
let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
layerInstruction.setTransform(
    CGAffineTransform(scaleX: scale, y: scale).concatenating(
        CGAffineTransform(translationX: screenRect.minX, y: screenRect.minY)
    ),
    at: .zero
)

let instruction = AVMutableVideoCompositionInstruction()
instruction.timeRange = CMTimeRange(start: .zero, duration: time(total))
instruction.layerInstructions = [layerInstruction]

let videoComposition = AVMutableVideoComposition()
videoComposition.renderSize = renderSize
videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
videoComposition.instructions = [instruction]

// All overlay images are full-canvas, so every layer shares one frame.
func imageLayer(_ name: String) -> CALayer {
    let image = NSImage(contentsOfFile: "\(layersPath)/\(name).png")!
    let layer = CALayer()
    layer.frame = CGRect(origin: .zero, size: renderSize)
    layer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    layer.contentsGravity = .resize
    return layer
}

func visible(_ layer: CALayer, from start: Double, to end: Double, fadeIn: Bool = true, fadeOut: Bool = true) {
    let a = max(start, 0) / total
    let b = min(end, total) / total
    let f = fade / total

    let animation = CAKeyframeAnimation(keyPath: "opacity")
    animation.values = [0, 0, 1, 1, 0, 0]
    animation.keyTimes = [
        0,
        NSNumber(value: fadeIn ? a : max(a - 0.0001, 0)),
        NSNumber(value: fadeIn ? a + f : a),
        NSNumber(value: fadeOut ? b - f : b),
        NSNumber(value: fadeOut ? b : min(b + 0.0001, 1)),
        1,
    ]
    animation.beginTime = AVCoreAnimationBeginTimeAtZero
    animation.duration = total
    animation.isRemovedOnCompletion = false
    animation.fillMode = .both
    layer.opacity = 0
    layer.add(animation, forKey: "visibility")
}

let parentLayer = CALayer()
parentLayer.frame = CGRect(origin: .zero, size: renderSize)
let videoLayer = CALayer()
videoLayer.frame = parentLayer.frame
parentLayer.addSublayer(videoLayer)
parentLayer.addSublayer(imageLayer("frame"))

for (index, range) in captionRanges {
    let caption = imageLayer("cap_\(index)")
    visible(caption, from: range.0, to: range.1, fadeIn: index != 0, fadeOut: true)
    parentLayer.addSublayer(caption)
}

let endCard = imageLayer("endcard")
visible(endCard, from: videoEnd - 0.3, to: total + 1, fadeIn: true, fadeOut: false)
parentLayer.addSublayer(endCard)

videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
    postProcessingAsVideoLayer: videoLayer,
    in: parentLayer
)

try? FileManager.default.removeItem(atPath: outputPath)
let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
export.videoComposition = videoComposition
export.outputURL = URL(fileURLWithPath: outputPath)
export.outputFileType = .mp4

let done = DispatchSemaphore(value: 0)
export.exportAsynchronously { done.signal() }
done.wait()

print("status:", export.status == .completed ? "completed" : "failed", "duration:", total)
