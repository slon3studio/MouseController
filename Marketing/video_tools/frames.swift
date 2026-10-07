import AVFoundation
import AppKit

// Dumps frames for checking a video: frames <video> <outdir> <step seconds> <width>
let args = CommandLine.arguments
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let step = Double(args[3])!
let width = Double(args[4])!
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
generator.maximumSize = CGSize(width: width, height: width * 3)
let duration = CMTimeGetSeconds(asset.duration)
print("duration", duration)
var t = 0.0
while t < duration {
    if let image = try? generator.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        try! data.write(to: URL(fileURLWithPath: String(format: "%@/f_%06.2f.png", args[2], t)))
    }
    t += step
}
