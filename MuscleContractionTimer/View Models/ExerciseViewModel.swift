//
//  ExerciseViewModel.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/14/26.
//

import Foundation
import Combine

class ExerciseViewModel: ObservableObject, Identifiable {
    
    var id: UUID { exercise.id }
    
    @Published var exercise: Exercise
    @Published var sets: [ExerciseSet]
    @Published var currentSet: Int?
    
    private var setCancellables: [AnyCancellable] = []
    
    init(exercise: Exercise, sets: [ExerciseSet]) {
        self.exercise = exercise
        self.sets = sets
        self.currentSet = sets.count > 0 ? 0 : nil
        bindSets()
    }
    
    func addSet() {
        sets.append(
            sets.last?.copy() ?? .init(weight: 0, reps: 0)
        )
        bindSets()
    }
    
    private func bindSets() {
        setCancellables = sets.map { set in
            set.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
    }
    
    var activeOrCurrentSet: ExerciseSet? {
        if let active = sets.first(where: { $0.state == .started }) {
            return active
        }
        if let current = currentSet, sets.indices.contains(current) {
            let set = sets[current]
            if set.state == .notStarted {
                return set
            }
        }
        if let next = sets.first(where: { $0.state == .notStarted }) {
            return next
        }
        return sets.last
    }
    
    var stateSymbol: String {
        activeOrCurrentSet?.stateSymbol ?? "play.fill"
    }
    
    @MainActor
    func cycleCurrentSetState() {
        if let active = sets.first(where: { $0.state == .started }) {
            active.cycleState()
            if let activeIndex = sets.firstIndex(where: { $0.id == active.id }) {
                currentSet = activeIndex < sets.count - 1 ? activeIndex + 1 : activeIndex
            }
        } else if let next = sets.first(where: { $0.state == .notStarted }) {
            next.cycleState()
            if let nextIndex = sets.firstIndex(where: { $0.id == next.id }) {
                currentSet = nextIndex
            }
        } else if let last = sets.last {
            last.cycleState()
        }
    }
}
