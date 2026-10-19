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
    @Published var reps: String  // not Int for simplicity with text input
    @Published var state: ExerciseSetState
    
    
    init(
        weight: Int, // Int instead of Double also for simplicity lol
        reps: Int,
        state: ExerciseSetState = .notStarted
    ) {
        self.weight = String(weight)
        self.reps = String(reps)
        self.state = state
    }
    
    fileprivate init(
        weight: String,
         reps: String,
         state: ExerciseSetState = .notStarted
    ) {
        self.weight = weight
        self.reps = reps
        self.state = state
    }
    
    func copy() -> ExerciseSet {
        return ExerciseSet(
            weight: self.weight,
            reps: self.reps,
            state: self.state
        )
    }

    func cycleState() {
        switch self.state {
        case .notStarted:
            self.state = .started
        case .started:
            self.state = .finished
        case .finished:
            self.state = .notStarted
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
