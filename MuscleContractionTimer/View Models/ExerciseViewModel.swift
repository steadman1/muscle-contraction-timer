//
//  ExerciseViewModel.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/14/26.
//

import Foundation
import Combine

class ExerciseViewModel: ObservableObject {
    
    @Published var exercise: Exercise
    @Published var sets: [ExerciseSet]
    @Published var currentSet: Int?
    
    init(exercise: Exercise, sets: [ExerciseSet]) {
        self.exercise = exercise
        self.sets = sets
        self.currentSet = sets.count > 0 ? 0 : nil
    }
    
    func addSet() {
        sets.append(
            sets.last?.copy() ?? .init(weight: 0, reps: 0)
        )
    }
}
