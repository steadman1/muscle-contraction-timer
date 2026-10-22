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
    /// Fraction of ROM above the resting trough that defines repetition start/end departure (default 0.03 = 3%)
    public var crestDepartureRatio: Double
    /// Fraction of recording start/end penalized against pre/post-set handling artifacts (default 0.12 = 12%)
    public var edgeExclusionRatio: Double
    
    public static func preset(for source: SensorSource) -> AnalyzerConfiguration {
        switch source {
        case .iPhone:
            return AnalyzerConfiguration(
                targetSampleRateHz: 100.0,
                highPassCutoffHz: 0.10,
                lowPassCutoffHz: 5.5,
                crestDepartureRatio: 0.03,
                edgeExclusionRatio: 0.12
            )
        case .airPods:
            return AnalyzerConfiguration(
                targetSampleRateHz: 50.0,
                highPassCutoffHz: 0.08,
                lowPassCutoffHz: 3.8,
                crestDepartureRatio: 0.03,
                edgeExclusionRatio: 0.12
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
        
        // 1. Core-Window PCA (computed over middle 70% to ignore pre/post-set handling motion)
        let worldVectors = resampled.map(\.acc)
        let pca = SignalProcessing.computePrincipalAxis(worldVectors)
        let principalAxis = pca.axis
        let rawProjectedAcc = worldVectors.map { simd_dot($0, principalAxis) }
        
        // 2. Bandpass filter acceleration
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
        
        // 3. Adaptive moving-baseline detrending window
        let totalDuration = resampled.last!.time - resampled.first!.time
        let expectedRepDuration = max(1.4, totalDuration / Double(max(1, targetRepCount + 1)))
        let detrendWindowSamples = max(
            Int(expectedRepDuration * 1.5 * config.targetSampleRateHz),
            Int(2.2 * config.targetSampleRateHz)
        )
        
        // 4. Integrate acceleration -> velocity -> displacement
        let rawVelocity = SignalProcessing.cumulativeTrapezoid(signal: zeroMeanAcc, dt: dt)
        let unorientedVelocity = SignalProcessing.detrendMovingBaseline(
            signal: rawVelocity,
            windowSamples: detrendWindowSamples
        )
        
        let rawDisplacement = SignalProcessing.cumulativeTrapezoid(signal: unorientedVelocity, dt: dt)
        let unorientedDisplacement = SignalProcessing.detrendMovingBaseline(
            signal: rawDisplacement,
            windowSamples: detrendWindowSamples
        )
        
        // 5. Orient displacement so Stationary Rest Baseline = Bottom Trough and Rep Excursion = Positive Peak
        let cleanDisplacement = SignalProcessing.orientExcursionPositive(
            displacement: unorientedDisplacement,
            velocity: unorientedVelocity
        )
        let isFlipped = zip(unorientedDisplacement, cleanDisplacement).contains { $0.0 * $0.1 < 0 }
        let cleanVelocity = isFlipped ? unorientedVelocity.map { -$0 } : unorientedVelocity
        let orientedAcc = isFlipped ? zeroMeanAcc.map { -$0 } : zeroMeanAcc
        
        // 6. Build KinematicSample array
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
        
        // 7. Segment into K repetitions prioritizing the central cadence cluster
        let cycles = segmentKRepetitions(
            targetK: targetRepCount,
            samples: samples,
            displacements: cleanDisplacement,
            velocities: cleanVelocity,
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
    
    // MARK: - Central Cadence Cluster K-Peak Selection
    
    private struct CandidatePeak {
        let index: Int
        let height: Double
        let rawProminence: Double
        let weightedProminence: Double
    }
    
    private static func segmentKRepetitions(
        targetK: Int,
        samples: [KinematicSample],
        displacements: [Double],
        velocities: [Double],
        expectedRepDuration: TimeInterval,
        config: AnalyzerConfiguration
    ) -> [DetectedCycle] {
        let n = displacements.count
        guard n > 10 else { return [] }
        
        // Minimum spacing between distinct rep turnaround peaks (at least 0.65s or 38% of expected rep duration)
        let minPeakSpacingSec = max(0.65, expectedRepDuration * 0.38)
        let minPeakDistSamples = max(5, Int(minPeakSpacingSec * config.targetSampleRateHz))
        
        // 1. Collect all local maxima
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
        
        // 2. Merge local maxima that occur within `minPeakDistSamples` (keep higher peak)
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
        
        // 3. Compute prominence and apply Tukey edge taper to suppress pre/post-set handling spikes
        let valleyWindow = max(minPeakDistSamples, Int(expectedRepDuration * config.targetSampleRateHz))
        var candidates: [CandidatePeak] = []
        
        for pkIdx in mergedMaxima {
            let leftLo = max(0, pkIdx - valleyWindow)
            let rightHi = min(n - 1, pkIdx + valleyWindow)
            let leftMin = displacements[leftLo...pkIdx].min() ?? displacements[pkIdx]
            let rightMin = displacements[pkIdx...rightHi].min() ?? displacements[pkIdx]
            
            let rawProm = (displacements[pkIdx] - leftMin) + (displacements[pkIdx] - rightMin)
            let u = Double(pkIdx) / Double(max(1, n - 1))
            let centerWeight = SignalProcessing.centralWindowWeight(
                normalizedPosition: u,
                edgeFraction: config.edgeExclusionRatio
            )
            
            candidates.append(
                CandidatePeak(
                    index: pkIdx,
                    height: displacements[pkIdx],
                    rawProminence: rawProm,
                    weightedProminence: rawProm * centerWeight
                )
            )
        }
        
        // 4. Filter out minor baseline noise ripples (< 20% of the median top-K prominence)
        let sortedByProm = candidates.sorted { $0.weightedProminence > $1.weightedProminence }
        let refCount = min(targetK, sortedByProm.count)
        let medianTopProm = sortedByProm[refCount / 2].rawProminence
        let viableCandidates = candidates.filter { $0.rawProminence >= medianTopProm * 0.22 }
        
        let selectedPeaks: [CandidatePeak]
        if viableCandidates.count <= targetK {
            selectedPeaks = sortedByProm.prefix(targetK).sorted { $0.index < $1.index }
        } else {
            // 5. Evaluate contiguous windows of K viable peaks [start ... start + K - 1]
            // to select the central, uniformly-spaced repetition cluster and reject edge outliers
            var bestWindowScore = -Double.infinity
            var bestWindowStart = 0
            
            for start in 0...(viableCandidates.count - targetK) {
                let slice = Array(viableCandidates[start..<(start + targetK)])
                let meanWeightedProm = slice.map(\.weightedProminence).reduce(0, +) / Double(targetK)
                
                // Reward uniform ROM consistency across the K reps
                let heights = slice.map(\.rawProminence)
                let meanHeight = max(1e-6, heights.reduce(0, +) / Double(targetK))
                let heightStd = sqrt(heights.reduce(0) { $0 + pow($1 - meanHeight, 2) } / Double(targetK))
                let romConsistency = 1.0 / (1.0 + 0.5 * (heightStd / meanHeight))
                
                // Reward consistent cadence (inter-peak intervals)
                var cadenceRegularity = 1.0
                if slice.count >= 3 {
                    var intervals: [Double] = []
                    for j in 1..<slice.count {
                        intervals.append(Double(slice[j].index - slice[j - 1].index))
                    }
                    let meanInt = max(1.0, intervals.reduce(0, +) / Double(intervals.count))
                    let intStd = sqrt(intervals.reduce(0) { $0 + pow($1 - meanInt, 2) } / Double(intervals.count))
                    cadenceRegularity = 1.0 / (1.0 + 0.6 * (intStd / meanInt))
                }
                
                let score = meanWeightedProm * romConsistency * cadenceRegularity
                if score > bestWindowScore {
                    bestWindowScore = score
                    bestWindowStart = start
                }
            }
            selectedPeaks = Array(viableCandidates[bestWindowStart..<(bestWindowStart + targetK)])
        }
        
        guard !selectedPeaks.isEmpty else { return [] }
        
        // 6. Partition each repetition around its turnaround peak [valleyLeft -> Peak -> valleyRight]
        var cycles: [DetectedCycle] = []
        var previousRepEndIdx = 0
        
        for (repNum, peak) in selectedPeaks.enumerated() {
            let pkIdx = peak.index
            
            // Left search bound: never overlap the previous rep's end, and never reach past the previous peak
            let maxLookback = Int(expectedRepDuration * 1.15 * config.targetSampleRateHz)
            let searchLeftBound: Int
            if repNum > 0 {
                searchLeftBound = max(previousRepEndIdx, pkIdx - maxLookback)
            } else {
                searchLeftBound = max(0, pkIdx - maxLookback)
            }
            
            // Right search bound: stop at or before the trough preceding the next peak
            let maxLookahead = Int(expectedRepDuration * 1.15 * config.targetSampleRateHz)
            let searchRightBound: Int
            if repNum + 1 < selectedPeaks.count {
                let nextPeakIdx = selectedPeaks[repNum + 1].index
                // Find the lowest valley point between pkIdx and nextPeakIdx as the hard boundary between reps
                var interRepMinIdx = pkIdx + 1
                var interRepMinVal = Double.infinity
                for i in (pkIdx + 1)..<nextPeakIdx {
                    if displacements[i] < interRepMinVal {
                        interRepMinVal = displacements[i]
                        interRepMinIdx = i
                    }
                }
                searchRightBound = min(pkIdx + maxLookahead, interRepMinIdx + 4)
            } else {
                searchRightBound = min(n - 1, pkIdx + maxLookahead)
            }
            
            let safeLeft = max(0, min(searchLeftBound, pkIdx - 1))
            let safeRight = min(n - 1, max(searchRightBound, pkIdx + 1))
            
            let (cycle, endIdx) = extractTwoPhaseRepetition(
                repIndex: repNum + 1,
                leftBound: safeLeft,
                turnPeakIdx: pkIdx,
                rightBound: safeRight,
                samples: samples,
                displacements: displacements,
                velocities: velocities,
                config: config
            )
            cycles.append(cycle)
            previousRepEndIdx = endIdx
        }
        
        return cycles
    }
    
    // MARK: - Inflection-Trough 2-Phase Boundary Extractor (No Isometric Split)
    
    private static func extractTwoPhaseRepetition(
        repIndex: Int,
        leftBound: Int,
        turnPeakIdx: Int,
        rightBound: Int,
        samples: [KinematicSample],
        displacements: [Double],
        velocities: [Double],
        config: AnalyzerConfiguration
    ) -> (cycle: DetectedCycle, endIdx: Int) {
        let peakVal = displacements[turnPeakIdx]
        
        // 1. Locate the pre-rep trough (lowest displacement before the peak in [leftBound...turnPeakIdx])
        // If there is a flat resting shelf, choose the LAST point in the bottom 3% of that shelf
        // right before the upward movement begins.
        var minLeftVal = Double.infinity
        var minLeftIdx = leftBound
        for i in leftBound...turnPeakIdx {
            if displacements[i] <= minLeftVal {
                minLeftVal = displacements[i]
                minLeftIdx = i
            }
        }
        
        // 2. Locate the post-rep trough (lowest displacement after the peak in [turnPeakIdx...rightBound])
        // Choose the FIRST point in the bottom 3% of the return trough so post-rep standing rest is excluded.
        var minRightVal = Double.infinity
        var minRightIdx = rightBound
        for i in turnPeakIdx...rightBound {
            if displacements[i] < minRightVal {
                minRightVal = displacements[i]
                minRightIdx = i
            }
        }
        
        let stroke1ROM = max(1e-4, peakVal - minLeftVal)
        let stroke2ROM = max(1e-4, peakVal - minRightVal)
        let avgROM = 0.5 * (stroke1ROM + stroke2ROM)
        
        let maxVel = (leftBound...rightBound).map { abs(velocities[$0]) }.max() ?? 0.1
        
        // 3. Refine Start Index: walk forward from `minLeftIdx` only while still flat on the resting floor
        // (< 3% of ROM departure and velocity < 5% of peak speed) to trim pre-rep standing stillness
        // without cutting into slow eccentric descents.
        let departFloor1 = minLeftVal + stroke1ROM * config.crestDepartureRatio
        let velFloor = maxVel * 0.05
        
        var startIdx = minLeftIdx
        while startIdx < turnPeakIdx - 2 {
            if displacements[startIdx] > departFloor1 && velocities[startIdx] > velFloor {
                break
            }
            startIdx += 1
        }
        // Step back 1 sample to include the exact onset inflection
        startIdx = max(minLeftIdx, startIdx - 1)
        
        // 4. Refine End Index: walk backward from `minRightIdx` only while flat on the post-rep resting floor
        let departFloor2 = minRightVal + stroke2ROM * config.crestDepartureRatio
        var endIdx = minRightIdx
        while endIdx > turnPeakIdx + 2 {
            if displacements[endIdx] > departFloor2 && (-velocities[endIdx]) > velFloor {
                break
            }
            endIdx -= 1
        }
        endIdx = min(minRightIdx, endIdx + 1)
        
        let maxIdx = samples.count - 1
        let safeStart = max(0, min(startIdx, maxIdx - 2))
        let safeTurn = max(safeStart + 1, min(turnPeakIdx, maxIdx - 1))
        let safeEnd = max(safeTurn + 1, min(endIdx, maxIdx))
        
        let cycle = DetectedCycle(
            index: repIndex,
            startTime: samples[safeStart].time,
            turnaroundTime: samples[safeTurn].time,
            endTime: samples[safeEnd].time,
            romMeters: avgROM,
            peakVelocity: maxVel
        )
        return (cycle, safeEnd)
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
