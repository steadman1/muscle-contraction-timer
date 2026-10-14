//
//  ExerciseViewModel.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/14/26.
//

import Foundation
import Combine

enum ExerciseSetState {
    case notStarted(index: Int), started(index: Int), finished(index: Int), missingSets
}

class ExerciseViewModel: ObservableObject {
    
    @Published var exercise: Exercise
    @Published var sets: [ExerciseSet] = []
    
    @Published var activeSet: ExerciseSetState
    
    init(exercise: Exercise, sets: [ExerciseSet]) {
        self.exercise = exercise
        self.sets = sets
        self.activeSet = !sets.isEmpty ? .notStarted(index: 0) : .missingSets
    }
    
}
