// Adopted from:
// https://stackoverflow.com/questions/51804365/why-is-fft-different-in-swift-than-in-python
import Accelerate
func fftAnalyzer(frameOfSamples: [Float]) -> ([Float], [Float]) {
    // As above, frameOfSamples = [1.0, 2.0, 3.0, 4.0]

    let frameCount = frameOfSamples.count

    let reals = UnsafeMutableBufferPointer<Float>.allocate(capacity: frameCount)
    defer {reals.deallocate()}
    let imags =  UnsafeMutableBufferPointer<Float>.allocate(capacity: frameCount)
    defer {imags.deallocate()}
    _ = reals.initialize(from: frameOfSamples)
    imags.initialize(repeating: 0.0)
    var complexBuffer = DSPSplitComplex(realp: reals.baseAddress!, imagp: imags.baseAddress!)

    let log2Size = Int(log2(Float(frameCount)))
    print(log2Size)

    guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2Size), FFTRadix(kFFTRadix2)) else {
        return ([],[])
    }
    defer {vDSP_destroy_fftsetup(fftSetup)}

    // Perform a forward FFT
    vDSP_fft_zip(fftSetup, &complexBuffer, 1, vDSP_Length(log2Size), FFTDirection(FFT_FORWARD))

    let realFloats = Array(reals)
    let imaginaryFloats = Array(imags)

    print(realFloats)
    print(imaginaryFloats)

    return (realFloats, imaginaryFloats)
}

func ifft(_ realFloats: [Float], _ imagFloats:[Float]) -> [Float] {
    // God damn it Apple, why does it take a whole function for something
    // that can be expressed as a single line in Python?
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
    print(log2Size)

    guard let fftSetup = vDSP_create_fftsetup(vDSP_Length(log2Size), FFTRadix(kFFTRadix2)) else {
        return []
    }
    defer {vDSP_destroy_fftsetup(fftSetup)}

    // Perform an inverse FFT
    vDSP_fft_zip(fftSetup, &complexBuffer, 1, vDSP_Length(log2Size), FFTDirection(FFT_INVERSE))

    var realSignal:[Float] = Array(reals)
    let imaginarySignal = Array(imags)
    // We need to scale down the result of ifft according to:
    // https://developer.apple.com/library/archive/documentation/Performance/Conceptual/vDSP_Programming_Guide/UsingFourierTransforms/UsingFourierTransforms.html
    var scale : Float = 1/Float(frameCount)
    vDSP_vsmul(realSignal, 1, &scale, &realSignal, 1, vDSP_Length(frameCount));

    print(realSignal)
    print(imaginarySignal)

    return realSignal
}

let x:[Float] = [1,2,3,4]
let (reals,imags) = fftAnalyzer(frameOfSamples:x)
_ = ifft(reals, imags)
//Printed
//[10.0, -2.0, -2.0, -2.0]
//[0.0, 2.0, 0.0, -2.0]
