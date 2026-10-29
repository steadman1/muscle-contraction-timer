//
//  ExerciseSet.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/14/26.
//

import Foundation
import Combine
import SwiftUI

public enum ExerciseSetState: Int, Sendable, Equatable {
    case notStarted, started, finished
}

@MainActor
public final class ExerciseSet: ObservableObject, Identifiable, Equatable {
    public let id = UUID()
    
    @Published public var weight: String
    @Published public var reps: String {
        didSet {
            if oldValue != reps, state == .finished, !recordedFrames.isEmpty {
                recomputeTimings()
            }
        }
    }
    @Published public var state: ExerciseSetState
    
    @Published public var setStarted: Date
    @Published public var setFinished: Date
    
    // Post-hoc Muscle Contraction Timings (Seconds)
    @Published public var eccentricDuration: TimeInterval?
    @Published public var concentricDuration: TimeInterval?
    @Published public var isAnalyzingContraction: Bool = false
    
    @Published public var configuration: AnalyzerConfiguration?
    @Published public var phaseOrder: ExercisePhaseOrder = .eccentricFirst
    
    public private(set) var recordedFrames: [RawMotionFrame] = []
    private var recordedSource: SensorSource = .iPhone
    private var recordedPhaseOrder: ExercisePhaseOrder = .eccentricFirst
    private var recordedConfiguration: AnalyzerConfiguration?
    
    public init(
        weight: Int,
        reps: Int,
        state: ExerciseSetState = .notStarted,
        configuration: AnalyzerConfiguration? = nil,
        phaseOrder: ExercisePhaseOrder = .eccentricFirst
    ) {
        self.weight = String(weight)
        self.reps = String(reps)
        self.state = state
        self.setStarted = Date()
        self.setFinished = Date()
        self.configuration = configuration
        self.phaseOrder = phaseOrder
        self.recordedPhaseOrder = phaseOrder
        self.recordedConfiguration = configuration
    }
    
    private init(
        weight: String,
        reps: String,
        state: ExerciseSetState = .notStarted,
        eccentricDuration: TimeInterval? = nil,
        concentricDuration: TimeInterval? = nil,
        recordedFrames: [RawMotionFrame] = [],
        configuration: AnalyzerConfiguration? = nil,
        phaseOrder: ExercisePhaseOrder = .eccentricFirst
    ) {
        self.weight = weight
        self.reps = reps
        self.state = state
        self.setStarted = Date()
        self.setFinished = Date()
        self.eccentricDuration = eccentricDuration
        self.concentricDuration = concentricDuration
        self.recordedFrames = recordedFrames
        self.configuration = configuration
        self.phaseOrder = phaseOrder
        self.recordedPhaseOrder = phaseOrder
        self.recordedConfiguration = configuration
    }
    
    public func copy() -> ExerciseSet {
        ExerciseSet(
            weight: self.weight,
            reps: self.reps,
            state: self.state,
            eccentricDuration: self.eccentricDuration,
            concentricDuration: self.concentricDuration,
            recordedFrames: self.recordedFrames,
            configuration: self.configuration,
            phaseOrder: self.phaseOrder
        )
    }

    public func cycleState() {
        switch self.state {
        case .notStarted:
            self.setStarted = Date()
            self.eccentricDuration = nil
            self.concentricDuration = nil
            self.state = .started
            SetMotionTracker.shared.beginTracking(for: self)
            
        case .started:
            self.setFinished = Date()
            self.state = .finished
            SetMotionTracker.shared.finishTracking(for: self)
            
        case .finished:
            SetMotionTracker.shared.cancelTracking(for: self)
            self.eccentricDuration = nil
            self.concentricDuration = nil
            self.recordedFrames.removeAll()
            self.state = .notStarted
        }
    }
    
    public func storeAndAnalyze(
        frames: [RawMotionFrame],
        source: SensorSource,
        configuration: AnalyzerConfiguration? = nil,
        phaseOrder: ExercisePhaseOrder? = nil
    ) {
        self.recordedFrames = frames
        self.recordedSource = source
        if let config = configuration {
            self.recordedConfiguration = config
            self.configuration = config
        }
        if let order = phaseOrder {
            self.recordedPhaseOrder = order
            self.phaseOrder = order
        }
        recomputeTimings()
    }
    
    public func recomputeTimings() {
        let targetReps = max(1, Int(reps) ?? 1)
        let framesSnapshot = recordedFrames
        let sourceSnapshot = recordedSource
        let orderSnapshot = recordedPhaseOrder
        let configSnapshot = recordedConfiguration ?? configuration ?? AnalyzerConfiguration.preset(for: sourceSnapshot)
        
        guard framesSnapshot.count > 20 else {
            self.eccentricDuration = 0
            self.concentricDuration = 0
            self.isAnalyzingContraction = false
            return
        }
        
        self.isAnalyzingContraction = true
        
        Task.detached(priority: .userInitiated) {
            let result = await OfflineCycleAnalyzer.analyze(
                frames: framesSnapshot,
                targetRepCount: targetReps,
                source: sourceSnapshot,
                configuration: configSnapshot,
                phaseOrder: orderSnapshot
            )
            let avgEcc = await result.averageEccentricDuration
            let avgCon = await result.averageConcentricDuration
            
            await MainActor.run { [weak self] in
                self?.eccentricDuration = avgEcc
                self?.concentricDuration = avgCon
                self?.isAnalyzingContraction = false
            }
        }
    }
    
    public static func == (lhs: ExerciseSet, rhs: ExerciseSet) -> Bool {
        lhs.id == rhs.id
    }
}

extension ExerciseSet {
    var stateSymbol: String {
        switch self.state {
        case .notStarted:
            "play.fill"
        case .started:
            "checkmark"
        case .finished:
            "checkmark"
        }
    }
    
    var stateStyle: (
        primaryText: Color,
        secondaryText: Color,
        foreground: Color,
        stroke: Color,
        cycleStateForeground: Color,
        cycleStateBackground: Color
    ) {
        switch self.state {
        case .notStarted:
            return (
                primaryText: Color.primaryText,
                secondaryText: Color.secondaryText,
                foreground: Color.clear,
                stroke: Color.border,
                cycleStateForeground: Color.primaryText,
                cycleStateBackground: Color.clear
            )
        case .started:
            return (
                primaryText: Color.primaryText,
                secondaryText: Color.secondaryText,
                foreground: Color.clear,
                stroke: Color.tertiaryText,
                cycleStateForeground: Color.primaryText,
                cycleStateBackground: Color.clear
            )
        case .finished:
            return (
                primaryText: Color.primaryFinished,
                secondaryText: Color.primaryFinished,
                foreground: Color.secondaryFinished,
                stroke: Color.primaryFinished.opacity(0.1),
                cycleStateForeground: Color.white,
                cycleStateBackground: Color.primaryFinished
            )
        }
    }
}
