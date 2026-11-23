import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox
import QuartzCore

// TEST ONLY, USES THE HARDWARE ENCODER: run it only through verify-hardware.sh ratelive.
// usage: ratelive W H default|lowlatency MBPS:SECONDS[,MBPS:SECONDS...]
// One HEVC session with HEVCEncoder.makeSession's properties, fed 60 fps of a still desktop with a
// moving band of text-like blocks (a sixth of the height); at each
// step of the schedule AverageBitRate and DataRateLimits change on the live session. Per second:
// the target, the output rate, frames in, out and dropped, and the encode latency.

let args = CommandLine.arguments
guard args.count == 5, let width = Int(args[1]), let height = Int(args[2]),
      args[3] == "default" || args[3] == "lowlatency" else {
    print("usage: ratelive W H default|lowlatency MBPS:SECONDS[,MBPS:SECONDS...]"); exit(2)
}
let lowLatency = args[3] == "lowlatency"
let schedule: [(mbps: Int, seconds: Int)] = args[4].split(separator: ",").compactMap {
    let p = $0.split(separator: ":"); guard p.count == 2, let m = Int(p[0]), let s = Int(p[1]) else { return nil }
    return (m, s)
}
let fps = 60

var spec: [CFString: Any] = [:]
if lowLatency { spec[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = true }
var made: VTCompressionSession?
let createStatus = VTCompressionSessionCreate(
    allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_HEVC,
    encoderSpecification: spec.isEmpty ? nil : spec as CFDictionary, imageBufferAttributes: nil,
    compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &made)
guard createStatus == noErr, let session = made else { print("create failed: \(createStatus)"); exit(1) }

func set(_ key: CFString, _ value: CFTypeRef) -> OSStatus { VTSessionSetProperty(session, key: key, value: value) }
func setRate(_ bps: Int) -> (OSStatus, OSStatus) {
    (set(kVTCompressionPropertyKey_AverageBitRate, bps as CFNumber),
     set(kVTCompressionPropertyKey_DataRateLimits, [bps / 8, 1] as CFArray))
}
_ = set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
_ = set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel)
_ = set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
_ = set(kVTCompressionPropertyKey_MaxKeyFrameInterval, (fps * 4) as CFNumber)
_ = set(kVTCompressionPropertyKey_ExpectedFrameRate, fps as CFNumber)
let first = setRate(schedule[0].mbps * 1_000_000)
VTCompressionSessionPrepareToEncodeFrames(session)
var hw: CFBoolean?
VTSessionCopyProperty(session, key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
                      allocator: nil, valueOut: &hw)
var encoderID: CFString?
VTSessionCopyProperty(session, key: kVTCompressionPropertyKey_EncoderID, allocator: nil, valueOut: &encoderID)
print("session \(width)x\(height) mode=\(args[3]) hardware=\(hw.map { CFBooleanGetValue($0) }.map(String.init) ?? "unreported") encoder=\(encoderID.map { $0 as String } ?? "unreported") set=\(first)")

let poolCount = 30
var pool: [CVPixelBuffer] = []
var seed: UInt64 = 0x9E3779B97F4A7C15
func rnd() -> UInt8 { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return UInt8(truncatingIfNeeded: seed) }
for i in 0..<poolCount {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
    guard let b = pb else { print("pixel buffer failed"); exit(1) }
    CVPixelBufferLockBaseAddress(b, [])
    let base = CVPixelBufferGetBaseAddress(b)!.assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(b)
    let block = 8
    for by in stride(from: 0, to: height, by: block) {
        for bx in stride(from: 0, to: width, by: block) {
            let bandTop = (i * height / poolCount) % height
            let inBand = by >= bandTop && by < bandTop + height / 6
            let glyph = inBand && (bx / block + by / block) % 2 == 0
            let v = glyph ? rnd() : UInt8(((bx / 64) * 17 + (by / 64) * 29) & 0xFF)
            for y in by..<min(by + block, height) {
                let p = base + y * row
                for x in bx..<min(bx + block, width) {
                    p[x * 4] = v; p[x * 4 + 1] = v &+ 40; p[x * 4 + 2] = v &+ 90; p[x * 4 + 3] = 255
                }
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(b, [])
    pool.append(b)
}

final class Tally {
    let lock = NSLock()
    var bytes = 0, out = 0, dropped = 0, latencies: [Double] = []
    func take() -> (Int, Int, Int, [Double]) {
        lock.lock(); defer { bytes = 0; out = 0; dropped = 0; latencies = []; lock.unlock() }
        return (bytes, out, dropped, latencies)
    }
}
let tally = Tally()
var totals = (bytes: 0, out: 0, dropped: 0, inFrames: 0)

var frame: Int64 = 0
let start = CACurrentMediaTime()
var stepStart = start
for (index, step) in schedule.enumerated() {
    if index > 0 {
        let r = setRate(step.mbps * 1_000_000)
        print("t=\(String(format: "%.1f", CACurrentMediaTime() - start)) set \(step.mbps) Mbps live: status \(r)")
    }
    for second in 0..<step.seconds {
        var inFrames = 0
        for _ in 0..<fps {
            let due = stepStart + Double(second) + Double(inFrames) / Double(fps)
            let wait = due - CACurrentMediaTime()
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            let sent = CACurrentMediaTime()
            let pts = CMTime(value: frame, timescale: CMTimeScale(fps))
            let status = VTCompressionSessionEncodeFrame(session, imageBuffer: pool[Int(frame) % poolCount],
                                                         presentationTimeStamp: pts, duration: .invalid,
                                                         frameProperties: nil, infoFlagsOut: nil) { status, _, sb in
                let latency = (CACurrentMediaTime() - sent) * 1000
                tally.lock.lock()
                if status == noErr, let sb {
                    tally.bytes += CMSampleBufferGetTotalSampleSize(sb); tally.out += 1; tally.latencies.append(latency)
                } else { tally.dropped += 1 }
                tally.lock.unlock()
            }
            if status != noErr { tally.lock.lock(); tally.dropped += 1; tally.lock.unlock() }
            frame += 1; inFrames += 1
        }
        let (bytes, out, dropped, lat) = tally.take()
        totals.bytes += bytes; totals.out += out; totals.dropped += dropped; totals.inFrames += inFrames
        let mean = lat.isEmpty ? 0 : lat.reduce(0, +) / Double(lat.count)
        let worst = lat.max() ?? 0
        print(String(format: "t=%4.1f target %3d Mbps  out %6.2f Mbps  in %2d out %2d dropped %2d  latency mean %5.1f ms max %5.1f ms",
                     CACurrentMediaTime() - start, step.mbps, Double(bytes) * 8 / 1_000_000, inFrames, out, dropped, mean, worst))
    }
    stepStart += Double(step.seconds)
}
VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
VTCompressionSessionInvalidate(session)
print("total in \(totals.inFrames) out \(totals.out) dropped \(totals.dropped)")
