//
//  ExerciseSet.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/14/26.
//

import Foundation
import Combine

enum ExerciseSetState: Int {
    case notStarted, started, finished
}

class ExerciseSet: ObservableObject {
    let id = UUID()
    
    @Published var weight: Double
    @Published var reps: Int
    @Published var state: ExerciseSetState
    
    init(weight: Double, reps: Int, state: ExerciseSetState = .notStarted) {
        self.weight = weight
        self.reps = reps
        self.state = state
    }
}

extension ExerciseSet: Identifiable {
    static func == (lhs: borrowing ExerciseSet, rhs: borrowing ExerciseSet) -> Bool {
        lhs.id == rhs.id
    }
}
