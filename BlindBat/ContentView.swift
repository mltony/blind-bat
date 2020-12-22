//
//  ContentView.swift
//  BlindBat
//
//  Created by Tony Malykh on 12/11/20.
//

import Accelerate
import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI

// Noise generating code is ported from Python:
// https://stackoverflow.com/questions/33933842/how-to-generate-noise-in-frequency-range-with-numpy
// However, the python code there is a low-quality translation of original matlab code with some obvious mistakes,
// so please use Matlab  code as a real reference.
private func fftfreq(_ n:Int, _ d:Float) -> [Float] {
    // Identical to numpy.fft.fftfreq
    // Returns frequencies for DFT
    var result = [Float](repeating: 0, count: n)
    for i in 0...n-1{
        if(i >= (n+1)/2) {
            result[i] = Float(i - n) / (Float(n)*d)
        } else {
            result[i] = Float(i) / (Float(n)*d)
        }
    }
    return result
}

private func ifft(_ realFloats: [Float], _ imagFloats:[Float]) -> [Float] {
    // God damn it Apple, why does it take a whole function for something
    // that can be expressed as a single line in Python?
    // I was hoping to make it identical to  numpy.fft.ifft()
    // Code for ifft adopted from fft code:
    // https://stackoverflow.com/questions/51804365/why-is-fft-different-in-swift-than-in-python
    // However, it only works for frameCount being a power of 2.
    // We need a DSP expert here to sort out non-power-of-2 case.
    let frameCount:Int = realFloats.count
    if (frameCount & (frameCount - 1) != 0) {
        // That means frameCount is NOT a power of 2!
        // raise Exception("Screw you Apple, there are even no exception in Swift! This is what happens if you let UI developer to design a language...")
        return []
    }
    if (realFloats.count != imagFloats.count) {
        return []
    }
    let log2Size = Int(log2(Float(frameCount)))
    //let nn:Int = Int(NSDecimalNumber(decimal:pow(2, log2Size)))
    //print(nn)

    let reals = UnsafeMutableBufferPointer<Float>.allocate(capacity: frameCount)
    defer {reals.deallocate()}
    let imags =  UnsafeMutableBufferPointer<Float>.allocate(capacity: frameCount)
    defer {imags.deallocate()}
    _ = reals.initialize(from: realFloats)
    _ = imags.initialize(from: imagFloats)
    var complexBuffer = DSPSplitComplex(realp: reals.baseAddress!, imagp: imags.baseAddress!)

    

    guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2Size), FFTRadix(kFFTRadix2)) else {
        return []
    }
    defer {vDSP_destroy_fftsetup(fftSetup)}

    // Perform an inverse FFT
    vDSP_fft_zip(fftSetup, &complexBuffer, 1, vDSP_Length(log2Size), FFTDirection(FFT_INVERSE))

    var realSignal:[Float] = Array(reals)
    //let imaginarySignal = Array(imags)
    // We need to scale down the result of ifft according to:
    // https://developer.apple.com/library/archive/documentation/Performance/Conceptual/vDSP_Programming_Guide/UsingFourierTransforms/UsingFourierTransforms.html
    var scale : Float = 1/Float(frameCount)
    vDSP_vsmul(realSignal, 1, &scale, &realSignal, 1, vDSP_Length(frameCount));

    //print(realSignal)
    //print(imaginarySignal)

    return realSignal
}

private func random() -> Float {
    // Really, Apple!?
    // https://stackoverflow.com/questions/25050309/swift-random-float-between-0-and-1
    return Float(arc4random()) / 0xFFFFFFFF
}

private func fftNoise(_ f:[Float]) -> [Float] {
    //f = np.array(f, dtype='complex')
    let n:Int = f.count
    let np:Int = (n-1)/2
    let phases:[Float] = (0..<np).map {_ in 2 * Float.pi * random()}
    var reals = [Float](repeating: 0, count: n)
    var imags = [Float](repeating: 0, count: n)
    reals[0] = f[0]
    reals[np + 1] = f[np + 1] // This is only needed when n is even; in case of odd n, this will be overwritten by the following loop.
    // Rotating positive frequencies in complex space by randomly generated phase.
    // Also assigning Negative frequencies to be complex conjugates of their positive counterparts.
    for i in 1...np {
        reals[i] = f[i] * cos(phases[i - 1])
        imags[i] = f[i] * sin(phases[i - 1])
        reals[n - i] = reals[i]
        imags[n - i] = -imags[i]
    }
    return ifft(reals, imags)
}

private func cropSignal(_ signal:[Float], _ samples: Int) -> [Float] {
    let n:Int = signal.count
    var transitions:[Int] = []
    for i in 1..<n {
        if (signal[i-1].sign != signal[i].sign) {
            transitions.append(i)
        }
    }
    let tc = transitions.count
    if (tc < 2) {
        return []
    }
    let t0 = transitions[0]
    for i in (1...(tc - 1)).reversed() {
        if (transitions[i] - t0 <= samples) {
            let result:[Float] = Array(signal[t0..<transitions[i]])
            return result
        }
    }
    return signal
}

private func bandLimitedNoise(minFreq: Float, maxFreq: Float, samples: Int, sampleRate: Int) -> [Float]{
    var samples2:Int = 1
    while (samples2 < samples) {
        samples2 *= 2
    }
    print("samples=\(samples) samples2=\(samples2)")
    let freqs = fftfreq(samples2, Float(1)/Float(sampleRate))
    var f = [Float](repeating: 0, count: samples2)
    var idx:[Int] = []
    var count:Int = 0
    for i in 0..<samples2 {
        var fi = freqs[i]
        if ((fi >= minFreq) && (fi <= maxFreq)) {
            idx.append(i)
            count += 1
        }
    }
    //print("idx", idx)
    if (count == 0) {
        // Perhaps band is too narrow, let's try to find a single closest frequency
        var bestDistance:Float = 1e15
        var bestIndex:Int = -1
        for i in 0..<samples2 {
            let distance = min(
                (freqs[i] - minFreq).magnitude,
                (freqs[i] - maxFreq).magnitude
            )
            if (distance < bestDistance) {
                bestDistance = distance 
                bestIndex = i
            }
        }
        idx.append(bestIndex)
    }
    for i in idx {
        f[i] = 1
    }
    var signal = fftNoise(f)
    return cropSignal(signal, samples)
}

private func normalizeSignal(_ x: [Float]) -> [Float] {
    var sumAbs:Float = 0
    for xi in x {
        sumAbs += xi.magnitude
    }
    let avgAbs: Float = sumAbs / Float(x.count)
    let factor:Float = 0.5 / avgAbs
    var result = [Float](repeating: 0, count: x.count)
    for i in 0..<x.count {
        result[i] = factor * x[i]
    }
    return result
}

// The following code was adopter from:
// https://gist.github.com/hotpaw2/4eb1ca16c138178113816e78b14dde8b
let wavHeader44 : [UInt8] = [
    0x52, 0x49, 0x46, 0x46, 0x24, 0x08, 0x00, 0x00,     // "RIFF.b.."
    0x57, 0x41, 0x56, 0x45, 0x66, 0x6d, 0x74, 0x20,     // "WAVEfmt."
    0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x02, 0x00,     // minimal canonical WAV header
    // offset to data       1 = PCM     2 = stereo      // stereo PCM
    0x80, 0xbb, 0x00, 0x00, 0x00, 0xee, 0x02, 0x00,
    //    0x0bb80 = 48k     0x02ee00 = 192k             // sample rate & bytes/second
    // 0x44, 0xac, 0x00, 0x00, 0x88, 0x58, 0x01, 0x00,
    // //    0xAC44 = 44.1k    0x15888 = 2 * sr
    0x04, 0x00, 0x10, 0x00, 0x64, 0x61, 0x74, 0x61,     // 2 Int16 samples, "data"
    // 4 bytes, 16 bits per sample
    0x00, 0x08, 0x00, 0x00                              // place holder
    // 0x0800 = 2048 as number of samples
    // followed by sample data
]
typealias Byte = UInt8
func int16IntoByteArray(_ value: Int16, byteArray : inout [Byte], index: inout Int) {
    let uintVal = UInt(bitPattern: Int(value))
    byteArray[index] = UInt8(uintVal         & 0x000000ff)
    index += 1
    byteArray[index] = UInt8((uintVal >>  8) & 0x000000ff)
    index += 1
}
func int32IntoByteArray(_ value: Int32, byteArray : inout [Byte], index: inout Int) {
    let uintVal = UInt(bitPattern: Int(value))
    byteArray[index] = UInt8(uintVal         & 0x000000ff)
    index += 1
    byteArray[index] = UInt8((uintVal >>  8) & 0x000000ff)
    index += 1
    byteArray[index] = UInt8((uintVal >> 16) & 0x000000ff)
    index += 1
    byteArray[index] = UInt8((uintVal >> 24) & 0x000000ff)
    index += 1
}
func makeWav(_ samples : [Float], vol: Float) -> Data {
    let wavHeaderSize = wavHeader44.count
    let n = samples.count
    let wavArraySize = wavHeaderSize + 4 * n + 8
    var wavArray = [UInt8](repeating: 0, count: Int(wavArraySize))

    for i in 0 ..< wavHeaderSize {
        wavArray[i] = wavHeader44[i]
    }
    var index: Int = wavHeaderSize
    let nBytes = Int32(4 * n)  // bytes
    int32IntoByteArray(nBytes, byteArray: &wavArray, index: &index)
    //var twoByteTemp : [UInt8] = [ 0 , 0 ]
    for i in 0 ..< n {
        let x = samples[i] * vol
        var b:Int16
        if (x > Float(Int16.max)) {
            b = Int16.max
        } else if (x < Float(Int16.min)) {
            b = Int16.min
        } else {
            b = Int16(x)
        }
        for _ in 0...1 {
            int16IntoByteArray(b, byteArray: &wavArray, index: &index)
        }
    }
    let d = Data(bytes: wavArray as [UInt8], count: wavArraySize)
    return(d)
}

func WriteWav(_ buff: [Float], _ url:URL, _ sampleRate:Int) {
    // https://stackoverflow.com/questions/42178958/write-array-of-floats-to-a-wav-audio-file-in-swift
    let SAMPLE_RATE =  Float64(sampleRate)

    let outputFormatSettings = [
        AVFormatIDKey:kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey:32,
        AVLinearPCMIsFloatKey: true,
        //  AVLinearPCMIsBigEndianKey: false,
        AVSampleRateKey: SAMPLE_RATE,
        AVNumberOfChannelsKey: 1
        ] as [String : Any]
    
    let audioFile = try? AVAudioFile(forWriting: url, settings: outputFormatSettings, commonFormat: AVAudioCommonFormat.pcmFormatFloat32, interleaved: true)

    let bufferFormat:AVAudioFormat = AVAudioFormat(settings: outputFormatSettings)!

    let outputBuffer:AVAudioPCMBuffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity: AVAudioFrameCount(2 * buff.count))!

    // i had my samples in doubles, so convert then write

    for i in 0..<buff.count {
        outputBuffer.floatChannelData!.pointee[2*i] = Float( buff[i] )
        outputBuffer.floatChannelData!.pointee[2*i+1] = Float( buff[i] )
    }
    outputBuffer.frameLength = AVAudioFrameCount( buff.count )

    do{
        try audioFile?.write(from: outputBuffer)

    } catch let error as NSError {
        print("error:", error.localizedDescription)
    }
}

var player: AVAudioPlayer?
func playSound(_ url:URL, continuously:Bool = false) {
    if (player != nil) {
        player!.stop()
    }
    do {
        //AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryAmbient, error: nil)
        //AVAudioSession.sharedInstance().setActive(true, error: nil)
        //try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)            
        try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.ambient, mode: .default)            
        try AVAudioSession.sharedInstance().setActive(true)

        /* The following line is required for the player to work on iOS 11. Change the file type accordingly*/
        player = try AVAudioPlayer(contentsOf: url, fileTypeHint: AVFileType.wav.rawValue)
        guard let player = player else { return }
        if (continuously) {
            player.numberOfLoops = -1
        }
        player.play()
    } catch let error {
        print(error.localizedDescription)
    }
}

let frequencies:[Int] = [
    200, 300, 400, 500, 600, 700, 800, 900, 
    1000, 1300, 1600,
    2000, 2500,
    3000, 3500,
    4000, 5000, 6000, 7000, 8000, 9000
]
var frequencyIndex:Int = UserDefaults.standard.integer(forKey: "frequencyIndex")
func registerAllDefaults() {
    UserDefaults.standard.register(defaults: [
        "frequencyPercentile" : 50,
        "frequencyBandwidthPercentile" : 50,
        "clickFrequency": 1,
        "clickLength": 30
    ])
}


struct ContentView: View {
    @State var frequencyPercentile:Float = UserDefaults.standard.float(forKey: "frequencyPercentile")
    @State var frequencyBandwidthPercentile:Float = UserDefaults.standard.float(forKey: "frequencyBandwidthPercentile")
    @State var clickFrequency:Float = UserDefaults.standard.float(forKey: "clickFrequency")
    @State var clickLength:Float = UserDefaults.standard.float(forKey: "clickLength")
    @State var isPlaying:Bool = false
    @State var playButtonText:String = "Play"
    
    private func getFrequency() -> Float {
        let minFreq:Float = 200
        let maxFreq:Float = 10000
        let ratio = maxFreq / minFreq
        return minFreq * pow(ratio, frequencyPercentile / 100)
    }
    private func getFrequencyBandwidth() -> Float {
        let minBw:Float = 10
        let maxBw:Float = 3000
        let ratio = maxBw / minBw
        return minBw * pow(ratio, frequencyBandwidthPercentile / 100)
    }    
    private func getHertzString(_ hertz: Float) -> String {
        let hertzInt:Int = Int(hertz)
        if (hertz >= 1000) {
            let major = hertzInt / 1000
            let minor = hertzInt % 1000 / 100
            return "\(major).\(minor) Kilohertz"
        } else {
            return "\(hertzInt) Hertz"
        }
    }

    var body: some View {
        VStack {
            Button(action: {
                self.playPause()
            }) {
                Text(self.playButtonText)
            }
        
            Text("Frequency")
            Slider(
                value: Binding<Float>(
                    get: {
                        self.frequencyPercentile
                    }, 
                    set: {
                        self.frequencyPercentile = $0
                        UserDefaults.standard.set(self.frequencyPercentile, forKey: "frequencyPercentile")
                        speak(getHertzString(getFrequency()))
                        updateClick()
                    }
                ),
                in:0...100,
                step:5
            )
            Text("Bandwidth")
            Slider(
                value: Binding<Float>(
                    get: {
                        self.frequencyBandwidthPercentile
                    }, 
                    set: {
                        self.frequencyBandwidthPercentile = $0
                        UserDefaults.standard.set(self.frequencyBandwidthPercentile, forKey: "frequencyBandwidthPercentile")
                        speak(getHertzString(getFrequencyBandwidth()))
                        updateClick()
                    }
                ),
                in:0...100,
                step:5
            )            
            Text("How many clicks per second")
            Slider(
                value: Binding<Float>(
                    get: {
                        self.clickFrequency
                    }, 
                    set: {
                        self.clickFrequency = $0
                        UserDefaults.standard.set(self.clickFrequency, forKey: "clickFrequency")
                        speak(getHertzString(self.clickFrequency))
                        updateClick()
                    }
                ),
                in:1...10,
                step:1
            )            
            Text("click duration")
            Slider(
                value: Binding<Float>(
                    get: {
                        self.clickLength
                    }, 
                    set: {
                        self.clickLength = $0
                        UserDefaults.standard.set(self.clickLength, forKey: "clickLength")
                        updateClick()
                    }
                ),
                in:5...100,
                step:5
            )                        
            Text("Hello, world!")
                .padding()
                .onAppear(perform: initialize)
        }
    }
    // User defaults:
    // https://www.hackingwithswift.com/books/ios-swiftui/storing-user-settings-with-userdefaults
    private func initialize() {
        /*
        print("Initialize!")
        var signal = bandLimitedNoise(minFreq:1000, maxFreq:2000, samples:5*48000, sampleRate:48000)
        signal = normalizeSignal(signal)
        let directory = NSTemporaryDirectory()
        let fileName = NSUUID().uuidString
        // This returns a URL? even though it is an NSURL class method
        let url:URL = NSURL.fileURL(withPathComponents: [directory, fileName])!
        //let url = URL(fileURLWithPath: "/Users/tony/1.wav")
        WriteWav(signal, url, 48000)
        playSound(url)
        sleep(5)
        playSound(url)
        */
        //updateClick()
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
            playPause()
            return MPRemoteCommandHandlerStatus.success
        }

        commandCenter.pauseCommand.addTarget { (commandEvent) -> MPRemoteCommandHandlerStatus in
            playPause()
            return MPRemoteCommandHandlerStatus.success
        }        
    }
    
    private func updateClick() {
        let sampleRate = 48000
        let samples:Int = Int(Float(sampleRate) / 1000 * clickLength)
        let totalSamples:Int = Int(Float(sampleRate) / clickFrequency) // This one includes silence after click
        let minFreq = max(
            100,
            getFrequency() - getFrequencyBandwidth() / 2
        )
        let maxFreq = getFrequency() + getFrequencyBandwidth() / 2
        var signal = bandLimitedNoise(minFreq:minFreq, maxFreq:maxFreq, samples:samples, sampleRate:sampleRate)
        signal = normalizeSignal(signal)
        
        while (signal.count < totalSamples) {
            signal.append(0)
        }
        let directory = NSTemporaryDirectory()
        let fileName = NSUUID().uuidString
        let url:URL = NSURL.fileURL(withPathComponents: [directory, fileName])!
        WriteWav(signal, url, 48000)
        if (isPlaying) {
            playSound(url, continuously:true)
        }
    }
    
    private func playPause() {
        self.isPlaying = !self.isPlaying
        if (self.isPlaying) {
            self.updateClick()
            playButtonText = "Pause"
        } else {
            if (player != nil) {
                player!.stop()
            }
            playButtonText = "Play"
        }
    }
    
    let synthesizer = AVSpeechSynthesizer()
    private func speak(_ str:String) {
        let utterance = AVSpeechUtterance(string: str)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.70
        synthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        synthesizer.speak(utterance)    
    }    
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
