//
//  SignalProcessing.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/13/26.
//

import Foundation
import Accelerate
import simd

public enum SignalProcessing {
    
    // MARK: - 1. Principal Component Analysis
    
    public static func computePrincipalAxis(_ vectors: [SIMD3<Double>]) -> (axis: SIMD3<Double>, explainedVariance: Double) {
        let n = Double(vectors.count)
        guard n > 3 else { return (SIMD3<Double>(0, 0, 1), 1.0) }
        
        let mean = vectors.reduce(SIMD3<Double>.zero, +) / n
        
        var c00 = 0.0, c01 = 0.0, c02 = 0.0
        var c11 = 0.0, c12 = 0.0, c22 = 0.0
        
        for v in vectors {
            let d = v - mean
            c00 += d.x * d.x
            c01 += d.x * d.y
            c02 += d.x * d.z
            c11 += d.y * d.y
            c12 += d.y * d.z
            c22 += d.z * d.z
        }
        
        let invN = 1.0 / (n - 1.0)
        var matrix: [Double] = [
            c00 * invN, c01 * invN, c02 * invN,
            c01 * invN, c11 * invN, c12 * invN,
            c02 * invN, c12 * invN, c22 * invN
        ]
        
        var jobz = Int8(UnicodeScalar("V").value)
        var uplo = Int8(UnicodeScalar("U").value)
        var dim = __CLPK_integer(3)
        var lda = __CLPK_integer(3)
        var eigenvalues = [Double](repeating: 0.0, count: 3)
        var lwork = __CLPK_integer(9)
        var work = [Double](repeating: 0.0, count: Int(lwork))
        var info = __CLPK_integer(0)
        
        dsyev_(&jobz, &uplo, &dim, &matrix, &lda, &eigenvalues, &work, &lwork, &info)
        
        let totalVariance = max(eigenvalues.reduce(0, +), 1e-12)
        let dominantVariance = eigenvalues[2]
        let principalAxis = simd_normalize(SIMD3<Double>(matrix[6], matrix[7], matrix[8]))
        
        return (principalAxis, dominantVariance / totalVariance)
    }
    
    // MARK: - 2. Zero-Phase Butterworth Filtering (filtfilt)
    
    public enum FilterPassType {
        case lowpass
        case highpass
    }
    
    public static func zeroPhaseButterworth(
        signal: [Double],
        cutoffHz: Double,
        sampleRateHz: Double,
        type: FilterPassType
    ) -> [Double] {
        guard signal.count > 6, cutoffHz > 0, cutoffHz < sampleRateHz * 0.5 else { return signal }
        
        let wc = tan(.pi * cutoffHz / sampleRateHz)
        let wc2 = wc * wc
        let sqrt2 = sqrt(2.0)
        let norm = 1.0 / (1.0 + sqrt2 * wc + wc2)
        
        let b0: Double, b1: Double, b2: Double
        switch type {
        case .lowpass:
            b0 = wc2 * norm
            b1 = 2.0 * b0
            b2 = b0
        case .highpass:
            b0 = 1.0 * norm
            b1 = -2.0 * b0
            b2 = b0
        }
        
        let a1 = 2.0 * (wc2 - 1.0) * norm
        let a2 = (1.0 - sqrt2 * wc + wc2) * norm
        
        // Pad signal with reflected endpoints to eliminate startup/ending filter transients
        let padLen = min(signal.count - 1, 60)
        var padded = [Double]()
        padded.reserveCapacity(signal.count + 2 * padLen)
        
        let leftAnchor = 2.0 * signal[0]
        for i in stride(from: padLen, through: 1, by: -1) {
            padded.append(leftAnchor - signal[i])
        }
        padded.append(contentsOf: signal)
        let rightAnchor = 2.0 * signal[signal.count - 1]
        for i in stride(from: signal.count - 2, through: signal.count - 1 - padLen, by: -1) {
            padded.append(rightAnchor - signal[i])
        }
        
        let forward = applyBiquad(padded, b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
        let reversed = Array(forward.reversed())
        let backward = applyBiquad(reversed, b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
        let unreversed = Array(backward.reversed())
        
        return Array(unreversed[padLen..<(padLen + signal.count)])
    }
    
    private static func applyBiquad(
        _ x: [Double],
        b0: Double, b1: Double, b2: Double,
        a1: Double, a2: Double
    ) -> [Double] {
        var y = [Double](repeating: 0.0, count: x.count)
        // Initialize state to steady-state DC value of first sample
        let dcGain = (b0 + b1 + b2) / (1.0 + a1 + a2)
        var z1 = x[0] * (b1 + b2 - (a1 + a2) * dcGain)
        var z2 = x[0] * (b2 - a2 * dcGain)
        
        for i in 0..<x.count {
            let xi = x[i]
            let yi = b0 * xi + z1
            z1 = b1 * xi - a1 * yi + z2
            z2 = b2 * xi - a2 * yi
            y[i] = yi
        }
        return y
    }
    
    // MARK: - 3. Numerical Integration & Moving-Window Detrending
    
    public static func cumulativeTrapezoid(signal: [Double], dt: Double) -> [Double] {
        guard signal.count > 1 else { return signal }
        var integrated = [Double](repeating: 0.0, count: signal.count)
        var sum = 0.0
        for i in 1..<signal.count {
            sum += 0.5 * (signal[i - 1] + signal[i]) * dt
            integrated[i] = sum
        }
        return integrated
    }
    
    /// Subtracts a two-pass (zero-phase) moving average baseline of `windowSamples` width,
    /// eliminating drift without bowing the signal endpoints or distorting flat isometric shelves.
    public static func detrendMovingBaseline(signal: [Double], windowSamples: Int) -> [Double] {
        let n = signal.count
        guard n > 4 else { return signal }
        let halfWin = max(2, min(n / 2, windowSamples / 2))
        
        func boxcarSmooth(_ input: [Double]) -> [Double] {
            var out = [Double](repeating: 0.0, count: n)
            var prefix = [Double](repeating: 0.0, count: n + 1)
            for i in 0..<n { prefix[i + 1] = prefix[i] + input[i] }
            
            for i in 0..<n {
                let lo = max(0, i - halfWin)
                let hi = min(n - 1, i + halfWin)
                out[i] = (prefix[hi + 1] - prefix[lo]) / Double(hi - lo + 1)
            }
            return out
        }
        
        // Two passes of boxcar smoothing = triangular zero-phase low-pass baseline
        let pass1 = boxcarSmooth(signal)
        let baseline = boxcarSmooth(pass1)
        
        var detrended = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            detrended[i] = signal[i] - baseline[i]
        }
        return detrended
    }
    
    // MARK: - 4. Automatic Rest-Baseline Polarity Calibration
    
    /// Determines whether the stationary rest baseline sits at the bottom (troughs) or top (crests)
    /// of the displacement wave. If the stationary rest periods sit at the troughs (like in IMG_0963 & IMG_0966
    /// where standing rest is at -25cm and squatting down peaks at +50cm), it ensures the wave is oriented
    /// so that Rest = Bottom Trough and Turnaround Excursion = Positive Peak (+cm).
    public static func orientExcursionPositive(displacement: [Double], velocity: [Double]) -> [Double] {
        let n = displacement.count
        guard n > 20 else { return displacement }
        
        // Compute 90th percentile of positive vs negative excursion relative to median
        let sortedDisp = displacement.sorted()
        let p10 = sortedDisp[max(0, Int(Double(n) * 0.10))]
        let p50 = sortedDisp[n / 2]
        let p90 = sortedDisp[min(n - 1, Int(Double(n) * 0.90))]
        
        // Also find the mean displacement of the quietest 30% of samples (stationary rest periods)
        let absVel = velocity.map(abs)
        let sortedVel = absVel.sorted()
        let quietVelCutoff = sortedVel[max(0, Int(Double(n) * 0.30))]
        
        var quietSum = 0.0
        var quietCount = 0.0
        for i in 0..<n where absVel[i] <= quietVelCutoff {
            quietSum += displacement[i]
            quietCount += 1.0
        }
        let quietMean = quietCount > 0 ? (quietSum / quietCount) : p50
        let midRange = 0.5 * (p10 + p90)
        
        // If stationary rest periods sit above the mid-range of the wave, invert the signal
        // so that rest periods always sit at the bottom trough and active rep excursions rise to positive peaks.
        if quietMean > midRange {
            return displacement.map { -$0 }
        } else {
            return displacement
        }
    }
}
