//
//  Example of Using AVAudioPlayer 
//    to play a buffer of (synthesized) audio samples from memory
//    by converting a [Float] buffer into an in-memory WAV file
//
//  Copyright © 2019 Ronald H Nicholson Jr. All rights reserved.
//  (re)Distribution permitted under the 3-clause New BSD license.
//

import Foundation
import AVFoundation

let t  =     2          // seconds duration to play

let sr  = 48000         // audio sample rate
let f0  =   660.0       // some test audio frequency
var vol =  8192.0       // some volume , with 32767.0 == Float(Int16.max)

var wavHeader44 : [UInt8] = [
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

var gTmp1 = 0

typealias Byte = UInt8
func int16IntoByteArray(_ value: Int16, byteArray : inout [Byte], index : Int) {
    let uintVal = UInt(bitPattern: Int(value))
    byteArray[index + 0] = UInt8(uintVal         & 0x000000ff)
    byteArray[index + 1] = UInt8((uintVal >>  8) & 0x000000ff)
}
func int32IntoByteArray(_ value: Int32, byteArray : inout [Byte], index : Int) {
    let uintVal = UInt(bitPattern: Int(value))
    byteArray[index + 0] = UInt8(uintVal         & 0x000000ff)
    byteArray[index + 1] = UInt8((uintVal >>  8) & 0x000000ff)
    byteArray[index + 2] = UInt8((uintVal >> 16) & 0x000000ff)
    byteArray[index + 3] = UInt8((uintVal >> 24) & 0x000000ff)
}

let wavArraySize = 44 + 4 * t * sr + 8
var wavArray = [UInt8](repeating: 0, count: Int(wavArraySize))
var samples : [Float] = [ 0.0 ]
var a   =     0.0       // initial sinewave phase angle

func makeSamples(_ n : Int) -> [Float] {
    samples = [Float](repeating: 0.0, count: n)
    let da = 2.0 * Double.pi * f0 / Double(sr)
    for i in 0 ..< n {
        let x = sin(a)      // example : make a sine wave
        a += da ; if a > 2.0 * Double.pi { a -= 2.0 * Double.pi }
        samples[i] = Float(x)
    }
    return(samples)
}

func fillWav(_ samples : [Float], _ n : Int) -> Data {
    for i in 0 ..< 44 {
        wavArray[i] = wavHeader44[i]
    }
    var fourByteTemp : [UInt8] = [ 0, 0, 0, 0 ]
    let nBytes = Int32(4 * n)  // bytes
    int32IntoByteArray(nBytes, byteArray: &fourByteTemp, index: 0)
    for i in 0 ..< 4 {
        wavArray[40 + i] = fourByteTemp[i]
    }
    var twoByteTemp : [UInt8] = [ 0 , 0 ]
    for i in 0 ..< n {
        let x = samples[i]
        let b = Int16(vol * Double(x))
        int16IntoByteArray(b, byteArray: &twoByteTemp, index: 0)
        wavArray[44+4*i+0] = twoByteTemp[0]
        wavArray[44+4*i+1] = twoByteTemp[1]     // stereo Right
        wavArray[44+4*i+2] = twoByteTemp[0]
        wavArray[44+4*i+3] = twoByteTemp[1]     // stereo Left
        // gTmp1 = i
    }
    let d = Data(bytes: wavArray as [UInt8], count: wavArraySize)
    return(d)
}

var gPlayer : AVAudioPlayer? = nil

func playTone() {
    print("start")
    do {
        let n = t * sr
        let samples = makeSamples(n)
        let myWavData = fillWav(samples, n)  // Data()
        let myFileTypeString = String(AVFileType.wav.rawValue)
        let player = try AVAudioPlayer(data: myWavData, fileTypeHint: myFileTypeString)
        gPlayer = player    // assign to global to prevent release on function return
        gPlayer?.prepareToPlay()
        gPlayer?.play()
        if (gPlayer != nil) { print("playing") }
        usleep(UInt32((t+1)*1000*1000)) // sleep 3 seconds before quitting
        print("done")
    } catch {
        print("an AVPlayer Init Error occured")
    }
}

// eof