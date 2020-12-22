//
//  ContentView.swift
//  BlindBat
//
//  Created by Tony Malykh on 12/11/20.
//

import Accelerate
import AVFoundation
import Darwin.C
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
            result[i] = Float(i - n) / d
        } else {
            result[i] = Float(i) / d
        }
    }
    return result
}
/*
private func ifft(_ realFloats: [Float], _ imagFloats:[Float]) -> [Float] {
    // God damn it Apple, why does it take a whole function for something
    // that can be expressed as a single line in Python?
    //Identical to  numpy.fft.ifft()
    // Code for ifft adopted from fft code:
    // https://stackoverflow.com/questions/51804365/why-is-fft-different-in-swift-than-in-python
    let frameCount = realFloats.count
    if (realFloats.count != imagFloats.count) {
        return []
    }

    let reals = UnsafeMutableBufferPointer<Float>.allocate(capacity: frameCount)
    defer {reals.deallocate()}
    let imags =  UnsafeMutableBufferPointer<Float>.allocate(capacity: frameCount)
    defer {imags.deallocate()}
    _ = reals.initialize(from: realFloats)
    _ = imags.initialize(from: imagFloats)
    var complexBuffer = DSPSplitComplex(realp: reals.baseAddress!, imagp: imags.baseAddress!)

    let log2Size = Int(log2(Float(frameCount)))
    //print(log2Size)

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
}*/
private func bandLimitedNoise(minFreq: Float, maxFreq: Float, samples: Int, sampleRate: Int) -> [Float]{
    print("Samples", samples, "sampleRate", sampleRate)
    let freqs = fftfreq(samples, Float(1)/Float(sampleRate))
    print("freqs", freqs)
    print("freqs.count", freqs.count)
    print("4575", freqs[4575], freqs[4576])
    var f = [Float](repeating: 0, count: samples)
    var idx:[Int] = []
    var count:Int = 0
    for i in 0..<samples {
        //usleep(100)
        //print("i", i, "freqs.count", freqs.count)
        if (i >= freqs.count) {
            return []
        }
        var fi = freqs[i]
        //print("fi", fi)
        //print((fi >= minFreq) && (fi <= maxFreq))
        if ((fi >= minFreq) && (fi <= maxFreq)) {
            //idx.append(i)
            count += 1
            //print("count", count)
        }
        //print("next loop!")
    }
    print("idx", idx)
    
    if (count == 0) {
        // Perhaps band is too narrow, let's try to find a single closest frequency
        var bestDistance:Float = 1e15
        var bestIndex:Int = -1
        for i in 0..<samples {
            let distance = min(
                (freqs[i] - minFreq).magnitude,
                (freqs[i] - maxFreq).magnitude
            )
            print("i", i, "distance", distance)
            fflush(stdout)
            if (distance < bestDistance) {
                print("Distance improved!")
                fflush(stdout)
                bestDistance = distance 
                bestIndex = i
            }
        }
        print("bestIndex", bestIndex)
        fflush(stdout)
        idx.append(bestIndex)
    }
    /*
    for i in idx {
        f[i] = 1
    }
    print(f)
    
    return fftNoise(f)
    */
    return []
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

if (true) {
    var signal = bandLimitedNoise(minFreq:1000, maxFreq:2000, samples:4800, sampleRate:48000)
}