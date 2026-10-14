//
//  OfflineCycleAnalyzer.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/13/26.
//

import Foundation
import simd

public struct AnalyzerConfiguration: Sendable {
    public var targetSampleRateHz: Double
    public var highPassCutoffHz: Double
    public var lowPassCutoffHz: Double
    public var stillnessVelocityThreshold: Double
    public var crestDepartureRatio: Double
    
    public static func preset(for source: SensorSource) -> AnalyzerConfiguration {
        switch source {
        case .iPhone:
            return AnalyzerConfiguration(
                targetSampleRateHz: 100.0,
                highPassCutoffHz: 0.12,
                lowPassCutoffHz: 6.0,
                stillnessVelocityThreshold: 0.12, // Fraction of stroke peak velocity considered stationary
                crestDepartureRatio: 0.04         // 4% of ROM departure threshold
            )
        case .airPods:
            return AnalyzerConfiguration(
                targetSampleRateHz: 50.0,
                highPassCutoffHz: 0.10,
                lowPassCutoffHz: 4.0,
                stillnessVelocityThreshold: 0.12,
                crestDepartureRatio: 0.04
            )
        }
    }
}

public enum OfflineCycleAnalyzer {
    
    public static func analyze(
        frames: [RawMotionFrame],
        targetRepCount: Int,
        source: SensorSource,
        configuration: AnalyzerConfiguration? = nil,
        phaseOrder: ExercisePhaseOrder = .eccentricFirst
    ) -> SessionAnalysisResult {
        let config = configuration ?? .preset(for: source)
        let dt = 1.0 / config.targetSampleRateHz
        
        guard targetRepCount > 0,
              frames.count > 20,
              let firstTime = frames.first?.timestamp,
              let lastTime = frames.last?.timestamp,
              (lastTime - firstTime) >= 1.0 else {
            return SessionAnalysisResult(
                source: source,
                phaseOrder: phaseOrder,
                principalAxis: SIMD3<Double>(0, 0, 1),
                explainedVarianceRatio: 0,
                samples: [],
                cycles: []
            )
        }
        
        let resampled = resampleUniformly(frames: frames, dt: dt)
        let n = resampled.count
        guard n > 15 else {
            return SessionAnalysisResult(
                source: source,
                phaseOrder: phaseOrder,
                principalAxis: SIMD3<Double>(0, 0, 1),
                explainedVarianceRatio: 0,
                samples: [],
                cycles: []
            )
        }
        
        // 1. PCA Principal Axis
        let worldVectors = resampled.map(\.acc)
        let pca = SignalProcessing.computePrincipalAxis(worldVectors)
        let principalAxis = pca.axis
        let rawProjectedAcc = worldVectors.map { simd_dot($0, principalAxis) }
        
        // 2. Bandpass filter acceleration (with reflected endpoint padding to prevent edge transients)
        let denoisedAcc = SignalProcessing.zeroPhaseButterworth(
            signal: rawProjectedAcc,
            cutoffHz: config.lowPassCutoffHz,
            sampleRateHz: config.targetSampleRateHz,
            type: .lowpass
        )
        let zeroMeanAcc = SignalProcessing.zeroPhaseButterworth(
            signal: denoisedAcc,
            cutoffHz: config.highPassCutoffHz,
            sampleRateHz: config.targetSampleRateHz,
            type: .highpass
        )
        
        // 3. Adaptive moving-baseline window based on average expected rep duration
        let totalDuration = resampled.last!.time - resampled.first!.time
        let expectedRepDuration = max(1.5, totalDuration / Double(max(1, targetRepCount)))
        let detrendWindowSamples = max(Int(expectedRepDuration * 1.6 * config.targetSampleRateHz), Int(2.5 * config.targetSampleRateHz))
        
        // 4. Integrate acceleration -> velocity & detrend
        let rawVelocity = SignalProcessing.cumulativeTrapezoid(signal: zeroMeanAcc, dt: dt)
        let unorientedVelocity = SignalProcessing.detrendMovingBaseline(
            signal: rawVelocity,
            windowSamples: detrendWindowSamples
        )
        
        // 5. Integrate velocity -> displacement & detrend
        let rawDisplacement = SignalProcessing.cumulativeTrapezoid(signal: unorientedVelocity, dt: dt)
        let unorientedDisplacement = SignalProcessing.detrendMovingBaseline(
            signal: rawDisplacement,
            windowSamples: detrendWindowSamples
        )
        
        // 6. Calibrate sign convention so Resting Baseline = Bottom Trough and Active Excursion = Positive Peak
        let cleanDisplacement = SignalProcessing.orientExcursionPositive(
            displacement: unorientedDisplacement,
            velocity: unorientedVelocity
        )
        // Keep velocity sign consistent with oriented displacement
        let isFlipped = zip(unorientedDisplacement, cleanDisplacement).contains { $0.0 * $0.1 < 0 }
        let cleanVelocity = isFlipped ? unorientedVelocity.map { -$0 } : unorientedVelocity
        let orientedAcc = isFlipped ? zeroMeanAcc.map { -$0 } : zeroMeanAcc
        
        // 7. Build KinematicSample array
        var samples: [KinematicSample] = []
        samples.reserveCapacity(n)
        for i in 0..<n {
            samples.append(
                KinematicSample(
                    id: i,
                    time: resampled[i].time,
                    worldAcceleration: resampled[i].acc,
                    projectedAcceleration: orientedAcc[i],
                    velocity: cleanVelocity[i],
                    displacement: cleanDisplacement[i]
                )
            )
        }
        
        // 8. Select the exact K Excursion Peaks and segment their [Start -> Iso -> End] boundaries
        let cycles = segmentKRepetitions(
            targetK: targetRepCount,
            samples: samples,
            displacements: cleanDisplacement,
            velocities: cleanVelocity,
            accelerations: orientedAcc,
            expectedRepDuration: expectedRepDuration,
            config: config
        )
        
        return SessionAnalysisResult(
            source: source,
            phaseOrder: phaseOrder,
            principalAxis: principalAxis,
            explainedVarianceRatio: pca.explainedVariance,
            samples: samples,
            cycles: cycles
        )
    }
    
    // MARK: - Peak-Anchored K-Repetition Segmentation
    
    private struct CandidatePeak {
        let index: Int
        let height: Double
        let prominence: Double
    }
    
    private static func segmentKRepetitions(
        targetK: Int,
        samples: [KinematicSample],
        displacements: [Double],
        velocities: [Double],
        accelerations: [Double],
        expectedRepDuration: TimeInterval,
        config: AnalyzerConfiguration
    ) -> [DetectedCycle] {
        let n = displacements.count
        guard n > 10 else { return [] }
        
        // Minimum distance between two distinct repetition turnaround peaks:
        // At least 40% of the average rep duration (or 0.65s minimum) so a double-bump at the bottom
        // of an isometric pause is merged into a single rep rather than counted as two reps.
        let minPeakSpacingSec = max(0.65, expectedRepDuration * 0.42)
        let minPeakDistSamples = max(5, Int(minPeakSpacingSec * config.targetSampleRateHz))
        
        // 1. Find all local maxima in `displacements`
        var rawMaxima: [Int] = []
        for i in 2..<(n - 2) {
            let v = displacements[i]
            if v >= displacements[i - 1] && v >= displacements[i - 2] &&
               v >= displacements[i + 1] && v >= displacements[i + 2] &&
               (v > displacements[i - 1] || v > displacements[i + 1]) {
                rawMaxima.append(i)
            }
        }
        
        guard !rawMaxima.isEmpty else { return [] }
        
        // 2. Merge local maxima that are closer than `minPeakDistSamples` (keep the higher peak)
        var mergedMaxima: [Int] = []
        for idx in rawMaxima {
            if let last = mergedMaxima.last, (idx - last) < minPeakDistSamples {
                if displacements[idx] > displacements[last] {
                    mergedMaxima[mergedMaxima.count - 1] = idx
                }
            } else {
                mergedMaxima.append(idx)
            }
        }
        
        // 3. Score each candidate peak by its prominence above surrounding valleys
        let valleyWindow = max(minPeakDistSamples, Int(expectedRepDuration * config.targetSampleRateHz))
        var candidates: [CandidatePeak] = []
        for pkIdx in mergedMaxima {
            let leftLo = max(0, pkIdx - valleyWindow)
            let rightHi = min(n - 1, pkIdx + valleyWindow)
            let leftMin = displacements[leftLo...pkIdx].min() ?? displacements[pkIdx]
            let rightMin = displacements[pkIdx...rightHi].min() ?? displacements[pkIdx]
            let prominence = (displacements[pkIdx] - leftMin) + (displacements[pkIdx] - rightMin)
            candidates.append(CandidatePeak(index: pkIdx, height: displacements[pkIdx], prominence: prominence))
        }
        
        // 4. Select top K peaks by prominence, then sort chronologically
        let selectedPeaks = candidates
            .sorted { $0.prominence > $1.prominence }
            .prefix(targetK)
            .sorted { $0.index < $1.index }
        
        guard !selectedPeaks.isEmpty else { return [] }
        
        // 5. For each turnaround peak, locate the bounding resting troughs [valleyLeft, valleyRight]
        // and refine the exact Phase 1, Isometric, and Phase 2 boundaries
        var cycles: [DetectedCycle] = []
        for (repNum, peak) in selectedPeaks.enumerated() {
            let pkIdx = peak.index
            
            // Search window for the resting trough before this peak:
            // Bounded by the previous rep's end (or up to 1.25x expectedRepDuration before the peak)
            let searchLeftBound: Int
            if repNum > 0 {
                let prevPeakIdx = selectedPeaks[repNum - 1].index
                // Start searching after the previous peak's descent finished
                searchLeftBound = prevPeakIdx + max(2, (pkIdx - prevPeakIdx) / 4)
            } else {
                searchLeftBound = max(0, pkIdx - Int(expectedRepDuration * 1.3 * config.targetSampleRateHz))
            }
            
            // Search window for the resting trough after this peak:
            let searchRightBound: Int
            if repNum + 1 < selectedPeaks.count {
                let nextPeakIdx = selectedPeaks[repNum + 1].index
                // Stop searching before the next rep's descent is well underway
                searchRightBound = pkIdx + min(
                    Int(expectedRepDuration * 0.85 * config.targetSampleRateHz),
                    (nextPeakIdx - pkIdx) * 3 / 4
                )
            } else {
                searchRightBound = min(n - 1, pkIdx + Int(expectedRepDuration * 1.1 * config.targetSampleRateHz))
            }
            
            let safeLeftBound = max(0, min(searchLeftBound, pkIdx - 1))
            let safeRightBound = min(n - 1, max(searchRightBound, pkIdx + 1))
            
            let cycle = extractSingleRepetition(
                repIndex: repNum + 1,
                leftBound: safeLeftBound,
                turnPeakIdx: pkIdx,
                rightBound: safeRightBound,
                samples: samples,
                displacements: displacements,
                velocities: velocities,
                config: config
            )
            cycles.append(cycle)
        }
        
        return cycles
    }
    
    // MARK: - Single Repetition Boundary & Isometric Plateau Extractor
    
    private static func extractSingleRepetition(
        repIndex: Int,
        leftBound: Int,
        turnPeakIdx: Int,
        rightBound: Int,
        samples: [KinematicSample],
        displacements: [Double],
        velocities: [Double],
        config: AnalyzerConfiguration
    ) -> DetectedCycle {
        // 1. Find the resting minimum before the peak (valleyLeft) and after the peak (valleyRight)
        // If there is a long flat rest between reps, pick the LAST minimum before the rise starts (for valleyLeft)
        // and the FIRST minimum after the descent finishes (for valleyRight).
        var minLeftVal = Double.infinity
        for i in leftBound...turnPeakIdx {
            if displacements[i] < minLeftVal { minLeftVal = displacements[i] }
        }
        var minRightVal = Double.infinity
        for i in turnPeakIdx...rightBound {
            if displacements[i] < minRightVal { minRightVal = displacements[i] }
        }
        
        let peakVal = displacements[turnPeakIdx]
        let stroke1ROM = max(1e-4, peakVal - minLeftVal)
        let stroke2ROM = max(1e-4, peakVal - minRightVal)
        let avgROM = 0.5 * (stroke1ROM + stroke2ROM)
        
        // 2. Locate maximum positive velocity during Phase 1 [leftBound...turnPeakIdx]
        // and maximum negative velocity during Phase 2 [turnPeakIdx...rightBound]
        var vPeak1Idx = leftBound
        var vPeak1 = 0.0
        for i in leftBound...turnPeakIdx {
            if velocities[i] > vPeak1 {
                vPeak1 = velocities[i]
                vPeak1Idx = i
            }
        }
        
        var vPeak2Idx = turnPeakIdx
        var vPeak2 = 0.0
        for i in turnPeakIdx...rightBound {
            if -velocities[i] > vPeak2 {
                vPeak2 = -velocities[i]
                vPeak2Idx = i
            }
        }
        
        let maxVel = max(vPeak1, vPeak2)
        
        // 3. Find Start of Phase 1 (`startIdx`):
        // Walk backward from `vPeak1Idx` toward `leftBound` until velocity drops below 10% of `vPeak1`
        // AND displacement is within the bottom 8% of the resting baseline.
        let vStartThresh = vPeak1 * max(0.08, config.stillnessVelocityThreshold * 0.75)
        let dispStartCeiling = minLeftVal + stroke1ROM * max(0.08, config.crestDepartureRatio * 2.0)
        
        var startIdx = vPeak1Idx
        while startIdx > leftBound {
            let prev = startIdx - 1
            // Stop walking back once we hit the flat resting floor (velocity near 0 or negative, and near bottom)
            if velocities[prev] <= vStartThresh && displacements[prev] <= dispStartCeiling {
                break
            }
            startIdx -= 1
        }
        
        // 4. Find End of Phase 1 (`phase1EndIdx`) and Start of Phase 2 (`phase2StartIdx`) around the Turnaround Peak:
        // Look at the plateau zone between `vPeak1Idx` (peak speed of Phase 1) and `vPeak2Idx` (peak speed of Phase 2).
        // Any region in `[vPeak1Idx ... vPeak2Idx]` where displacement is in the top 25% of the peak AND
        // velocity magnitude is below the stillness threshold is the true Isometric Hold.
        let isoDispFloor = peakVal - 0.25 * min(stroke1ROM, stroke2ROM)
        let isoVelThresh1 = vPeak1 * config.stillnessVelocityThreshold
        let isoVelThresh2 = vPeak2 * config.stillnessVelocityThreshold
        
        // Walk forward from vPeak1Idx until positive velocity drops below isoVelThresh1 near the top
        var phase1EndIdx = turnPeakIdx
        for i in vPeak1Idx...turnPeakIdx {
            if displacements[i] >= isoDispFloor && velocities[i] <= isoVelThresh1 {
                phase1EndIdx = i
                break
            }
        }
        
        // Walk backward from vPeak2Idx until negative velocity magnitude drops below isoVelThresh2 near the top
        var phase2StartIdx = turnPeakIdx
        for i in stride(from: vPeak2Idx, through: turnPeakIdx, by: -1) {
            if displacements[i] >= isoDispFloor && (-velocities[i]) <= isoVelThresh2 {
                phase2StartIdx = i
                break
            }
        }
        
        // 5. Find End of Phase 2 (`endIdx`):
        // Walk forward from `vPeak2Idx` toward `rightBound` until downward velocity settles back to baseline
        let vEndThresh = vPeak2 * max(0.08, config.stillnessVelocityThreshold * 0.75)
        let dispEndCeiling = minRightVal + stroke2ROM * max(0.08, config.crestDepartureRatio * 2.0)
        
        var endIdx = vPeak2Idx
        while endIdx < rightBound {
            let next = endIdx + 1
            if (-velocities[next]) <= vEndThresh && displacements[next] <= dispEndCeiling {
                break
            }
            endIdx += 1
        }
        
        // Enforce strict monotonic ordering
        let maxIdx = samples.count - 1
        let safeStart = max(0, min(startIdx, maxIdx))
        let safeEnd = max(safeStart + 2, min(endIdx, maxIdx))
        let safeP1End = max(safeStart + 1, min(phase1EndIdx, safeEnd - 1))
        let safeP2Start = max(safeP1End, min(phase2StartIdx, safeEnd - 1))
        
        return DetectedCycle(
            index: repIndex,
            startTime: samples[safeStart].time,
            phase1EndTime: samples[safeP1End].time,
            phase2StartTime: samples[safeP2Start].time,
            endTime: samples[safeEnd].time,
            romMeters: avgROM,
            peakVelocity: maxVel
        )
    }
    
    // MARK: - Uniform Interpolation Resampler
    
    private static func resampleUniformly(
        frames: [RawMotionFrame],
        dt: Double
    ) -> [(time: TimeInterval, acc: SIMD3<Double>)] {
        guard let startTime = frames.first?.timestamp,
              let endTime = frames.last?.timestamp else { return [] }
        
        let duration = endTime - startTime
        let totalSteps = Int(duration / dt)
        guard totalSteps > 1 else { return [] }
        
        var result: [(TimeInterval, SIMD3<Double>)] = []
        result.reserveCapacity(totalSteps)
        
        var frameCursor = 0
        for step in 0..<totalSteps {
            let targetRelativeTime = Double(step) * dt
            let targetAbsTime = startTime + targetRelativeTime
            
            while frameCursor + 1 < frames.count && frames[frameCursor + 1].timestamp < targetAbsTime {
                frameCursor += 1
            }
            
            if frameCursor + 1 < frames.count {
                let f0 = frames[frameCursor]
                let f1 = frames[frameCursor + 1]
                let span = f1.timestamp - f0.timestamp
                let alpha = span > 1e-6 ? (targetAbsTime - f0.timestamp) / span : 0.0
                let clampedAlpha = min(max(alpha, 0.0), 1.0)
                
                let acc0 = f0.worldAccelerationMetersPerSecSq
                let acc1 = f1.worldAccelerationMetersPerSecSq
                result.append((targetRelativeTime, acc0 + (acc1 - acc0) * clampedAlpha))
            } else {
                result.append((targetRelativeTime, frames[frameCursor].worldAccelerationMetersPerSecSq))
            }
        }
        
        return result
    }
}
