//
//  ExerciseSet.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/14/26.
//

import Foundation
import Combine
import SwiftUI

enum ExerciseSetState: Int {
    case notStarted, started, finished
}

class ExerciseSet: ObservableObject {
    let id = UUID()
    
    @Published var weight: String // not Double for simplicity with text input
    @Published var reps: String { // not Int for simplicity with text input
        didSet {
            if oldValue != reps, state == .finished, !recordedFrames.isEmpty {
                recomputeTimings()
            }
        }
    }
    @Published var state: ExerciseSetState
    
    @Published var setStarted: Date
    @Published var setFinished: Date
    
    // Post-hoc Muscle Contraction Timings (Seconds)
    @Published var eccentricDuration: TimeInterval?
    @Published var concentricDuration: TimeInterval?
    @Published var isAnalyzingContraction: Bool = false
    
    private(set) var recordedFrames: [RawMotionFrame] = []
    private var recordedSource: SensorSource = .iPhone
    private var recordedPhaseOrder: ExercisePhaseOrder = .eccentricFirst
    
    init(
        weight: Int, // Int instead of Double also for simplicity lol
        reps: Int,
        state: ExerciseSetState = .notStarted
    ) {
        self.weight = String(weight)
        self.reps = String(reps)
        self.state = state
        self.setStarted = Date()
        self.setFinished = Date()
    }
    
    fileprivate init(
        weight: String,
        reps: String,
        state: ExerciseSetState = .notStarted,
        eccentricDuration: TimeInterval? = nil,
        concentricDuration: TimeInterval? = nil,
        recordedFrames: [RawMotionFrame] = []
    ) {
        self.weight = weight
        self.reps = reps
        self.state = state
        self.setStarted = Date()
        self.setFinished = Date()
        self.eccentricDuration = eccentricDuration
        self.concentricDuration = concentricDuration
        self.recordedFrames = recordedFrames
    }
    
    func copy() -> ExerciseSet {
        return ExerciseSet(
            weight: self.weight,
            reps: self.reps,
            state: self.state,
            eccentricDuration: self.eccentricDuration,
            concentricDuration: self.concentricDuration,
            recordedFrames: self.recordedFrames
        )
    }

    @MainActor
    func cycleState() {
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
    
    func storeAndAnalyze(
        frames: [RawMotionFrame],
        source: SensorSource,
        phaseOrder: ExercisePhaseOrder
    ) {
        self.recordedFrames = frames
        self.recordedSource = source
        self.recordedPhaseOrder = phaseOrder
        recomputeTimings()
    }
    
    func recomputeTimings() {
        let targetReps = max(1, Int(reps) ?? 1)
        let framesSnapshot = recordedFrames
        let sourceSnapshot = recordedSource
        let orderSnapshot = recordedPhaseOrder
        
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
}

extension ExerciseSet: Identifiable {
    static func == (lhs: borrowing ExerciseSet, rhs: borrowing ExerciseSet) -> Bool {
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
