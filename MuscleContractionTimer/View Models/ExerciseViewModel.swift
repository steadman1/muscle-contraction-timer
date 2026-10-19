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
    @Published var sets: [ExerciseSet] = []
    
    init(exercise: Exercise, sets: [ExerciseSet]) {
        self.exercise = exercise
        self.sets = sets
    }
}
