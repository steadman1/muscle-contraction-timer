//
//  ExerciseViewModel.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/14/26.
//

import Foundation
import Combine

@MainActor
public final class ExerciseViewModel: ObservableObject, Identifiable {
    
    public var id: UUID { exercise.id }
    
    @Published public var exercise: Exercise {
        didSet {
            propagateExerciseConfigurationToSets()
        }
    }
    @Published public var sets: [ExerciseSet]
    @Published public var currentSet: Int?
    
    private var setCancellables: [AnyCancellable] = []
    
    public init(exercise: Exercise, sets: [ExerciseSet]) {
        self.exercise = exercise
        self.sets = sets
        self.currentSet = sets.count > 0 ? 0 : nil
        propagateExerciseConfigurationToSets()
        bindSets()
    }
    
    public func propagateExerciseConfigurationToSets() {
        let source = SetMotionTracker.shared.selectedSource
        let config = exercise.configuration(for: source)
        for set in sets {
            set.phaseOrder = exercise.phaseOrder
            set.configuration = config
        }
    }
    
    func addSet() {
        let source = SetMotionTracker.shared.selectedSource
        let config = exercise.configuration(for: source)
        let newSet = sets.last?.copy() ?? ExerciseSet(
            weight: 0,
            reps: 0,
            configuration: config,
            phaseOrder: exercise.phaseOrder
        )
        newSet.configuration = config
        newSet.phaseOrder = exercise.phaseOrder
        sets.append(newSet)
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
