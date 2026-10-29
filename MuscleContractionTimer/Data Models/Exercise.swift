//
//  Exercise.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/14/26.
//

import SwiftUI

/// Exercise-specific motion algorithm parameters optimized for biomechanical profile and sensor source.
public struct ExerciseMotionConfiguration: Sendable, Equatable, Hashable {
    public var defaultPhaseOrder: ExercisePhaseOrder
    public var iPhoneConfig: AnalyzerConfiguration
    public var airPodsConfig: AnalyzerConfiguration
    
    public init(
        defaultPhaseOrder: ExercisePhaseOrder,
        iPhoneConfig: AnalyzerConfiguration,
        airPodsConfig: AnalyzerConfiguration
    ) {
        self.defaultPhaseOrder = defaultPhaseOrder
        self.iPhoneConfig = iPhoneConfig
        self.airPodsConfig = airPodsConfig
    }
    
    public func configuration(for source: SensorSource) -> AnalyzerConfiguration {
        switch source {
        case .iPhone:
            return iPhoneConfig
        case .airPods:
            return airPodsConfig
        }
    }
    
    public mutating func updateConfiguration(_ config: AnalyzerConfiguration, for source: SensorSource) {
        switch source {
        case .iPhone:
            iPhoneConfig = config
        case .airPods:
            airPodsConfig = config
        }
    }
    
    public static func preset(for exerciseName: String) -> ExerciseMotionConfiguration {
        let lower = exerciseName.lowercased()
        if lower.contains("squat") {
            return .squat
        } else if lower.contains("pull") && (lower.contains("up") || lower.contains("down")) {
            return .pullUp
        } else {
            return .standard
        }
    }
    
    /// Optimized configuration for Squats (Back Squat, Front Squat, Goblet Squat):
    /// - Phase Sequence: Eccentric first (downward descent into the hole, inflection, upward concentric drive)
    /// - iPhone: 100 Hz, high-pass 0.07 Hz (preserves slow 4s descent), low-pass 4.8 Hz (cleans bar shake),
    ///   crest departure 0.028 (accurately pinpoints knee unlock/hip break while ignoring standing sway),
    ///   edge exclusion 0.16 (tapers walkout and rerack shock).
    /// - AirPods: 50 Hz, high-pass 0.06 Hz, low-pass 3.5 Hz, crest departure 0.028, edge exclusion 0.16.
    public static var squat: ExerciseMotionConfiguration {
        ExerciseMotionConfiguration(
            defaultPhaseOrder: .eccentricFirst,
            iPhoneConfig: AnalyzerConfiguration.squatPreset(for: .iPhone),
            airPodsConfig: AnalyzerConfiguration.squatPreset(for: .airPods)
        )
    }
    
    /// Optimized configuration for Pull Ups & Chin Ups:
    /// - Phase Sequence: Concentric first (upward pull from dead hang, chin over bar turnaround, eccentric lowering)
    /// - iPhone: 100 Hz, high-pass 0.06 Hz (preserves prolonged dead hangs and slow negative descents),
    ///   low-pass 3.8 Hz (filters sagittal body swing harmonics), crest departure 0.020 (instant onset
    ///   detection at first lat engagement from dead hang for maximum IoU), edge exclusion 0.18
    ///   (excludes jump-to-bar and drop-to-floor shocks).
    /// - AirPods: 50 Hz, high-pass 0.05 Hz, low-pass 3.0 Hz, crest departure 0.020, edge exclusion 0.18.
    public static var pullUp: ExerciseMotionConfiguration {
        ExerciseMotionConfiguration(
            defaultPhaseOrder: .concentricFirst,
            iPhoneConfig: AnalyzerConfiguration.pullUpPreset(for: .iPhone),
            airPodsConfig: AnalyzerConfiguration.pullUpPreset(for: .airPods)
        )
    }
    
    /// Standard baseline configuration for traditional strength exercises
    public static var standard: ExerciseMotionConfiguration {
        ExerciseMotionConfiguration(
            defaultPhaseOrder: .eccentricFirst,
            iPhoneConfig: AnalyzerConfiguration.preset(for: .iPhone),
            airPodsConfig: AnalyzerConfiguration.preset(for: .airPods)
        )
    }
}

public struct Exercise: Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var equipmentName: String
    public var demonstrationImage: Image
    public var motionConfiguration: ExerciseMotionConfiguration
    
    public var phaseOrder: ExercisePhaseOrder {
        get { motionConfiguration.defaultPhaseOrder }
        set { motionConfiguration.defaultPhaseOrder = newValue }
    }
    
    public init(
        id: UUID = UUID(),
        name: String,
        equipmentName: String,
        demonstrationImage: Image,
        motionConfiguration: ExerciseMotionConfiguration? = nil
    ) {
        self.id = id
        self.name = name
        self.equipmentName = equipmentName
        self.demonstrationImage = demonstrationImage
        self.motionConfiguration = motionConfiguration ?? .preset(for: name)
    }
    
    public func configuration(for source: SensorSource) -> AnalyzerConfiguration {
        motionConfiguration.configuration(for: source)
    }
    
    public static func squat(
        name: String = "Back Squat",
        equipmentName: String = "Barbell",
        demonstrationImage: Image = Image("squat")
    ) -> Exercise {
        Exercise(
            name: name,
            equipmentName: equipmentName,
            demonstrationImage: demonstrationImage,
            motionConfiguration: .squat
        )
    }
    
    public static func pullUp(
        name: String = "Pull Ups",
        equipmentName: String = "Pull Up Bar",
        demonstrationImage: Image = Image("pull_up")
    ) -> Exercise {
        Exercise(
            name: name,
            equipmentName: equipmentName,
            demonstrationImage: demonstrationImage,
            motionConfiguration: .pullUp
        )
    }
}

