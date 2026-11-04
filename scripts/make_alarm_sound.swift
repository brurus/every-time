// Renders the nap alarm (29 s, under the 30 s notification-sound limit) as IMA4 in a CAF, a quarter of PCM size.
// A soft, low chime that swells from a whisper (-36 dB) to full over 24 s, then holds; the system alarm
// can't ramp its own volume, so the swell lives in the file.
// Run: swift scripts/make_alarm_sound.swift
import Foundation

let rate = 22_050
let seconds = 29.0
let swell = 24.0
let notes = [523.3, 659.3, 784.0, 880.0, 784.0, 659.3]
let noteGap = 0.32, phrase = 2.4

func loudness(_ t: Double) -> Double { pow(10, -36 * max(0, 1 - t / swell) / 20) }

var samples = [Double](repeating: 0, count: Int(seconds * Double(rate)))
var start = 0.0
while start < seconds - 1 {
    for (i, freq) in notes.enumerated() {
        let onset = start + Double(i) * noteGap
        // A brighter overtone joins as it gets loud, so the full alarm still cuts through.
        let bright = max(0, min(1, (onset - swell / 2) / (swell / 2)))
        for n in Int(onset * Double(rate))..<min(samples.count, Int((onset + 1.4) * Double(rate))) {
            let t = Double(n) / Double(rate) - onset
            let tone = sin(2 * .pi * freq * t) + 0.3 * sin(4 * .pi * freq * t) + 0.2 * bright * sin(6 * .pi * freq * t)
            samples[n] += loudness(onset) * 0.32 * tone * exp(-t * 3) * min(1, t * 60)
        }
    }
    start += phrase
}
let peak = samples.map(abs).max() ?? 1
samples = samples.map { $0 * 0.9 / peak }

var data = Data()
func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + samples.count * 2))
data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
data.append(contentsOf: Array("data".utf8)); append(UInt32(samples.count * 2))
for s in samples { append(Int16(max(-1, min(1, s)) * 32_000)) }
let wav = FileManager.default.temporaryDirectory.appendingPathComponent("nap-alarm.wav")
try! data.write(to: wav)
let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
convert.arguments = ["-f", "caff", "-d", "ima4", wav.path, "EveryTime/Features/Sleep/Nap/nap-alarm.caf"]
try! convert.run()
convert.waitUntilExit()
