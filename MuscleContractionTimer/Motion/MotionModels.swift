//
//  MotionModels.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/13/26.
//

import Foundation
import CoreMotion
import simd

public enum SensorSource: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case iPhone = "iPhone"
    case airPods = "AirPods"
    
    public var id: String { rawValue }
}

public enum ContractionPhase: String, Codable, Hashable, Sendable {
    case eccentric = "Eccentric"
    case concentric = "Concentric"
}

public enum ExercisePhaseOrder: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case eccentricFirst = "Eccentric → Concentric"
    case concentricFirst = "Concentric → Eccentric"
    
    public var id: String { rawValue }
    
    public var firstPhase: ContractionPhase {
        self == .eccentricFirst ? .eccentric : .concentric
    }
    
    public var secondPhase: ContractionPhase {
        self == .eccentricFirst ? .concentric : .eccentric
    }
}

/// Packed 8-byte-aligned 3x3 matrix to avoid 16-byte SIMD alignment faults in large SwiftUI arrays.
public struct RotationMatrix3x3: Codable, Hashable, Sendable {
    public let m11: Double, m12: Double, m13: Double
    public let m21: Double, m22: Double, m23: Double
    public let m31: Double, m32: Double, m33: Double
    
    public init(from r: CMRotationMatrix) {
        self.m11 = r.m11; self.m12 = r.m12; self.m13 = r.m13
        self.m21 = r.m21; self.m22 = r.m22; self.m23 = r.m23
        self.m31 = r.m31; self.m32 = r.m32; self.m33 = r.m33
    }
    
    public init(simdMatrix: simd_double3x3) {
        let c0 = simdMatrix.columns.0
        let c1 = simdMatrix.columns.1
        let c2 = simdMatrix.columns.2
        self.m11 = c0.x; self.m12 = c1.x; self.m13 = c2.x
        self.m21 = c0.y; self.m22 = c1.y; self.m23 = c2.y
        self.m31 = c0.z; self.m32 = c1.z; self.m33 = c2.z
    }
    
    public func multiply(_ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            m11 * v.x + m12 * v.y + m13 * v.z,
            m21 * v.x + m22 * v.y + m23 * v.z,
            m31 * v.x + m32 * v.y + m33 * v.z
        )
    }
}

/// Raw immutable snapshot captured at 50-100Hz during recording.
public struct RawMotionFrame: Codable, Hashable, Sendable {
    public let timestamp: TimeInterval
    public let ax: Double
    public let ay: Double
    public let az: Double
    public let rotation: RotationMatrix3x3
    
    private enum CodingKeys: String, CodingKey {
        case timestamp
        case ax, ay, az
        case rotation
        case userAcceleration
        case col0, col1, col2
    }
    
    public init(from motion: CMDeviceMotion) {
        self.timestamp = motion.timestamp
        self.ax = motion.userAcceleration.x
        self.ay = motion.userAcceleration.y
        self.az = motion.userAcceleration.z
        self.rotation = RotationMatrix3x3(from: motion.attitude.rotationMatrix)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        
        if let rot = try? container.decode(RotationMatrix3x3.self, forKey: .rotation),
           let x = try? container.decode(Double.self, forKey: .ax),
           let y = try? container.decode(Double.self, forKey: .ay),
           let z = try? container.decode(Double.self, forKey: .az) {
            self.ax = x
            self.ay = y
            self.az = z
            self.rotation = rot
        } else {
            let acc = try container.decode(SIMD3<Double>.self, forKey: .userAcceleration)
            let c0 = try container.decode(SIMD3<Double>.self, forKey: .col0)
            let c1 = try container.decode(SIMD3<Double>.self, forKey: .col1)
            let c2 = try container.decode(SIMD3<Double>.self, forKey: .col2)
            self.ax = acc.x
            self.ay = acc.y
            self.az = acc.z
            self.rotation = RotationMatrix3x3(simdMatrix: simd_double3x3(columns: (c0, c1, c2)))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(ax, forKey: .ax)
        try container.encode(ay, forKey: .ay)
        try container.encode(az, forKey: .az)
        try container.encode(rotation, forKey: .rotation)
    }
    
    public var worldAccelerationMetersPerSecSq: SIMD3<Double> {
        let g = 9.80665
        let bodyAcc = SIMD3<Double>(ax, ay, az)
        return rotation.multiply(bodyAcc) * g
    }
}

/// Complete raw dataset persisted to disk for regression testing and offline algorithm evaluation.
public struct PersistedMotionSet: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public let source: SensorSource
    public var phaseOrder: ExercisePhaseOrder
    public var targetRepCount: Int
    public let frames: [RawMotionFrame]
    public let groundTruthReps: [GroundTruthRep]
    
    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        source: SensorSource,
        phaseOrder: ExercisePhaseOrder,
        targetRepCount: Int,
        frames: [RawMotionFrame],
        groundTruthReps: [GroundTruthRep]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.source = source
        self.phaseOrder = phaseOrder
        self.targetRepCount = targetRepCount
        self.frames = frames
        self.groundTruthReps = groundTruthReps
    }
    
    public var duration: TimeInterval {
        guard let first = frames.first?.timestamp, let last = frames.last?.timestamp else { return 0 }
        return max(0, last - first)
    }
}

/// A single sample point along the principal movement axis after offline processing.
public struct KinematicSample: Identifiable, Sendable {
    public let id: Int
    public let time: TimeInterval
    public let worldAcceleration: SIMD3<Double>
    public let projectedAcceleration: Double
    public let velocity: Double
    public let displacement: Double
    
    public init(
        id: Int = 0,
        time: TimeInterval,
        worldAcceleration: SIMD3<Double>,
        projectedAcceleration: Double,
        velocity: Double,
        displacement: Double
    ) {
        self.id = id
        self.time = time
        self.worldAcceleration = worldAcceleration
        self.projectedAcceleration = projectedAcceleration
        self.velocity = velocity
        self.displacement = displacement
    }
}

/// Represents one complete bi-directional movement cycle partitioned at `turnaroundTime`.
public struct DetectedCycle: Identifiable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let startTime: TimeInterval
    public let turnaroundTime: TimeInterval
    public let endTime: TimeInterval
    public let romMeters: Double
    public let peakVelocity: Double
    
    public var totalDuration: TimeInterval { max(0, endTime - startTime) }
    public var phase1Duration: TimeInterval { max(0, turnaroundTime - startTime) }
    public var phase2Duration: TimeInterval { max(0, endTime - turnaroundTime) }
    
    public func eccentricDuration(for order: ExercisePhaseOrder) -> TimeInterval {
        order == .eccentricFirst ? phase1Duration : phase2Duration
    }
    
    public func concentricDuration(for order: ExercisePhaseOrder) -> TimeInterval {
        order == .eccentricFirst ? phase2Duration : phase1Duration
    }
}

/// Represents a manually marked repetition with Start, Turnaround, and End timestamps.
/// Backward-compatible with JSON files saved under the previous schema.
public struct GroundTruthRep: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let index: Int
    public let startTime: TimeInterval
    public let turnaroundTime: TimeInterval
    public let endTime: TimeInterval
    
    private enum CodingKeys: String, CodingKey {
        case id, index, startTime, turnaroundTime, endTime
        // Legacy keys from isometric schema
        case phase1EndTime, phase2StartTime
    }
    
    public init(
        id: UUID = UUID(),
        index: Int,
        startTime: TimeInterval,
        turnaroundTime: TimeInterval,
        endTime: TimeInterval
    ) {
        self.id = id
        self.index = index
        self.startTime = startTime
        self.turnaroundTime = turnaroundTime
        self.endTime = endTime
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.index = try container.decode(Int.self, forKey: .index)
        self.startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        self.endTime = try container.decode(TimeInterval.self, forKey: .endTime)
        
        if let turn = try? container.decode(TimeInterval.self, forKey: .turnaroundTime) {
            self.turnaroundTime = turn
        } else {
            let p1End = (try? container.decode(TimeInterval.self, forKey: .phase1EndTime)) ?? self.startTime
            let p2Start = (try? container.decode(TimeInterval.self, forKey: .phase2StartTime)) ?? p1End
            self.turnaroundTime = 0.5 * (p1End + p2Start)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(index, forKey: .index)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(turnaroundTime, forKey: .turnaroundTime)
        try container.encode(endTime, forKey: .endTime)
    }
    
    public var totalDuration: TimeInterval { max(0, endTime - startTime) }
    public var phase1Duration: TimeInterval { max(0, turnaroundTime - startTime) }
    public var phase2Duration: TimeInterval { max(0, endTime - turnaroundTime) }
    
    public func eccentricDuration(for order: ExercisePhaseOrder) -> TimeInterval {
        order == .eccentricFirst ? phase1Duration : phase2Duration
    }
    
    public func concentricDuration(for order: ExercisePhaseOrder) -> TimeInterval {
        order == .eccentricFirst ? phase2Duration : phase1Duration
    }
}

/// Evaluates temporal accuracy between a detected cycle and a manual ground-truth interval.
public struct RepAccuracyComparison: Identifiable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let phaseOrder: ExercisePhaseOrder
    public let detected: DetectedCycle
    public let groundTruth: GroundTruthRep
    
    public var startError: TimeInterval { detected.startTime - groundTruth.startTime }
    public var turnaroundError: TimeInterval { detected.turnaroundTime - groundTruth.turnaroundTime }
    public var endError: TimeInterval { detected.endTime - groundTruth.endTime }
    public var durationError: TimeInterval { detected.totalDuration - groundTruth.totalDuration }
    
    public var eccentricDurationError: TimeInterval {
        detected.eccentricDuration(for: phaseOrder) - groundTruth.eccentricDuration(for: phaseOrder)
    }
    
    public var concentricDurationError: TimeInterval {
        detected.concentricDuration(for: phaseOrder) - groundTruth.concentricDuration(for: phaseOrder)
    }
    
    public var intersectionOverUnion: Double {
        let intersectionStart = max(detected.startTime, groundTruth.startTime)
        let intersectionEnd = min(detected.endTime, groundTruth.endTime)
        let intersection = max(0.0, intersectionEnd - intersectionStart)
        
        let unionStart = min(detected.startTime, groundTruth.startTime)
        let unionEnd = max(detected.endTime, groundTruth.endTime)
        let union = max(1e-9, unionEnd - unionStart)
        
        return intersection / union
    }
}

/// Complete report returned by the offline analyzer.
public struct SessionAnalysisResult: Sendable {
    public let source: SensorSource
    public let phaseOrder: ExercisePhaseOrder
    public let principalAxis: SIMD3<Double>
    public let explainedVarianceRatio: Double
    public let samples: [KinematicSample]
    public let cycles: [DetectedCycle]
    public let groundTruthReps: [GroundTruthRep]
    
    public init(
        source: SensorSource,
        phaseOrder: ExercisePhaseOrder = .eccentricFirst,
        principalAxis: SIMD3<Double>,
        explainedVarianceRatio: Double,
        samples: [KinematicSample],
        cycles: [DetectedCycle],
        groundTruthReps: [GroundTruthRep] = []
    ) {
        self.source = source
        self.phaseOrder = phaseOrder
        self.principalAxis = principalAxis
        self.explainedVarianceRatio = explainedVarianceRatio
        self.samples = samples
        self.cycles = cycles
        self.groundTruthReps = groundTruthReps
    }
    
    public var cycleCount: Int { cycles.count }
    
    public var averageDuration: TimeInterval {
        guard !cycles.isEmpty else { return 0 }
        return cycles.map(\.totalDuration).reduce(0, +) / Double(cycles.count)
    }
    
    public var averageEccentricDuration: TimeInterval {
        guard !cycles.isEmpty else { return 0 }
        return cycles.map { $0.eccentricDuration(for: phaseOrder) }.reduce(0, +) / Double(cycles.count)
    }
    
    public var averageConcentricDuration: TimeInterval {
        guard !cycles.isEmpty else { return 0 }
        return cycles.map { $0.concentricDuration(for: phaseOrder) }.reduce(0, +) / Double(cycles.count)
    }
    
    public var averageROMCentimeters: Double {
        guard !cycles.isEmpty else { return 0 }
        return (cycles.map(\.romMeters).reduce(0, +) / Double(cycles.count)) * 100.0
    }
    
    public var accuracyComparisons: [RepAccuracyComparison] {
        let count = min(cycles.count, groundTruthReps.count)
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            RepAccuracyComparison(
                index: i + 1,
                phaseOrder: phaseOrder,
                detected: cycles[i],
                groundTruth: groundTruthReps[i]
            )
        }
    }
    
    public var meanAbsoluteEccentricError: TimeInterval? {
        let comps = accuracyComparisons
        guard !comps.isEmpty else { return nil }
        return comps.map { abs($0.eccentricDurationError) }.reduce(0, +) / Double(comps.count)
    }
    
    public var meanAbsoluteConcentricError: TimeInterval? {
        let comps = accuracyComparisons
        guard !comps.isEmpty else { return nil }
        return comps.map { abs($0.concentricDurationError) }.reduce(0, +) / Double(comps.count)
    }
    
    public var meanAbsoluteTurnaroundError: TimeInterval? {
        let comps = accuracyComparisons
        guard !comps.isEmpty else { return nil }
        return comps.map { abs($0.turnaroundError) }.reduce(0, +) / Double(comps.count)
    }
    
    public var meanIoU: Double? {
        let comps = accuracyComparisons
        guard !comps.isEmpty else { return nil }
        return comps.map(\.intersectionOverUnion).reduce(0, +) / Double(comps.count)
    }
}
