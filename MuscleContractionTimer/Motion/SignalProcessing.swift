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
    
    // MARK: - 1. Core-Window Principal Component Analysis
    
    /// Computes the dominant 3D movement axis using only the central 70% [15%...85%] of the recording
    /// so pre-set and post-set phone/barbell handling noise does not skew the eigenvector.
    public static func computePrincipalAxis(_ vectors: [SIMD3<Double>]) -> (axis: SIMD3<Double>, explainedVariance: Double) {
        let total = vectors.count
        guard total > 6 else { return (SIMD3<Double>(0, 0, 1), 1.0) }
        
        let trimStart = Int(Double(total) * 0.15)
        let trimEnd = max(trimStart + 4, Int(Double(total) * 0.85))
        let coreSlice = vectors[trimStart..<min(total, trimEnd)]
        let n = Double(coreSlice.count)
        
        let mean = coreSlice.reduce(SIMD3<Double>.zero, +) / n
        
        var c00 = 0.0, c01 = 0.0, c02 = 0.0
        var c11 = 0.0, c12 = 0.0, c22 = 0.0
        
        for v in coreSlice {
            let d = v - mean
            c00 += d.x * d.x
            c01 += d.x * d.y
            c02 += d.x * d.z
            c11 += d.y * d.y
            c12 += d.y * d.z
            c22 += d.z * d.z
        }
        
        let invN = 1.0 / max(1.0, n - 1.0)
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
        
        let pass1 = boxcarSmooth(signal)
        let baseline = boxcarSmooth(pass1)
        
        var detrended = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            detrended[i] = signal[i] - baseline[i]
        }
        return detrended
    }
    
    // MARK: - 4. Core-Window Rest-Baseline Polarity Calibration
    
    /// Inspects the central 70% of the recording to orient the displacement wave so that
    /// Stationary Rest = Bottom Trough and Active Repetition Turnaround = Positive Peak (+cm).
    public static func orientExcursionPositive(displacement: [Double], velocity: [Double]) -> [Double] {
        let total = displacement.count
        guard total > 20 else { return displacement }
        
        let lo = Int(Double(total) * 0.15)
        let hi = max(lo + 10, Int(Double(total) * 0.85))
        let coreDisp = Array(displacement[lo..<min(total, hi)])
        let coreVel = Array(velocity[lo..<min(total, hi)])
        let n = coreDisp.count
        
        let sortedDisp = coreDisp.sorted()
        let p10 = sortedDisp[max(0, Int(Double(n) * 0.10))]
        let p50 = sortedDisp[n / 2]
        let p90 = sortedDisp[min(n - 1, Int(Double(n) * 0.90))]
        
        let absVel = coreVel.map(abs)
        let sortedVel = absVel.sorted()
        let quietVelCutoff = sortedVel[max(0, Int(Double(n) * 0.35))]
        
        var quietSum = 0.0
        var quietCount = 0.0
        for i in 0..<n where absVel[i] <= quietVelCutoff {
            quietSum += coreDisp[i]
            quietCount += 1.0
        }
        let quietMean = quietCount > 0 ? (quietSum / quietCount) : p50
        let midRange = 0.5 * (p10 + p90)
        
        if quietMean > midRange {
            return displacement.map { -$0 }
        } else {
            return displacement
        }
    }
    
    // MARK: - 5. Tukey Cosine Edge Taper Weight
    
    /// Returns a weight in [0.15, 1.0] that penalizes candidate peaks near the very start or end
    /// of the recording (where pre-set setup and post-set racking artifacts occur) while keeping
    /// the middle [edgeFraction ... 1 - edgeFraction] at full weight 1.0.
    public static func centralWindowWeight(normalizedPosition u: Double, edgeFraction: Double = 0.12) -> Double {
        let clampedU = min(max(u, 0.0), 1.0)
        guard edgeFraction > 0 else { return 1.0 }
        if clampedU < edgeFraction {
            let phase = clampedU / edgeFraction
            return 0.15 + 0.85 * 0.5 * (1.0 - cos(.pi * phase))
        } else if clampedU > (1.0 - edgeFraction) {
            let phase = (1.0 - clampedU) / edgeFraction
            return 0.15 + 0.85 * 0.5 * (1.0 - cos(.pi * phase))
        } else {
            return 1.0
        }
    }
}
