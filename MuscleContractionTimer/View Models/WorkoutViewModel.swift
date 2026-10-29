//
//  WorkoutViewModel.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/23/26.
//

import SwiftUI
import Combine

@MainActor
public final class WorkoutViewModel: ObservableObject, Identifiable {
    public let id = UUID()
    
    public let name: String
    
    @Published public var exercises: [ExerciseViewModel] = []
    @Published public var currentExerciseIndex: Int = 0
    @Published public var workoutStartDate: Date?
    @Published public var now: Date = Date()
    @Published public var heartRateString: String = "—"
    
    private var exerciseCancellables: [AnyCancellable] = []
    private var timerCancellable: AnyCancellable?
    private let motionTracker = SetMotionTracker.shared
    
    public init(name: String, exercises: [ExerciseViewModel] = []) {
        self.name = name
        self.exercises = exercises
        self.workoutStartDate = Date()
        
        bindExercises()
        startTimer()
    }
    
    deinit {
        timerCancellable?.cancel()
    }
    
    // MARK: - Exercise Management
    
    public func addExercise(_ exercise: Exercise, sets: [ExerciseSet] = []) {
        let initialSets = sets.isEmpty ? [
            ExerciseSet(weight: 135, reps: 8),
            ExerciseSet(weight: 135, reps: 8),
            ExerciseSet(weight: 135, reps: 8)
        ] : sets
        
        let newVM = ExerciseViewModel(exercise: exercise, sets: initialSets)
        exercises.append(newVM)
        bindExercises()
    }
    
    public func addExerciseViewModel(_ exerciseViewModel: ExerciseViewModel) {
        exercises.append(exerciseViewModel)
        bindExercises()
    }
    
    public func removeExercise(at offsets: IndexSet) {
        exercises.remove(atOffsets: offsets)
        if currentExerciseIndex >= exercises.count {
            currentExerciseIndex = max(0, exercises.count - 1)
        }
        bindExercises()
    }
    
    public func removeExercise(id: UUID) {
        exercises.removeAll { $0.id == id }
        if currentExerciseIndex >= exercises.count {
            currentExerciseIndex = max(0, exercises.count - 1)
        }
        bindExercises()
    }
    
    public func bindExercises() {
        exerciseCancellables = exercises.map { [weak self] vm in
            vm.objectWillChange.sink { [weak self, weak vm] _ in
                guard let self = self else { return }
                if let vm = vm {
                    self.syncTimingsToStore(for: vm)
                }
                self.objectWillChange.send()
            }
        }
    }
    
    // MARK: - Persistence & Tracking of Timings
    
    public func syncTimingsToStore(for targetVM: ExerciseViewModel? = nil) {
        let vmsToSync = targetVM.map { [$0] } ?? exercises
        for vm in vmsToSync {
            for (index, set) in vm.sets.enumerated() {
                if set.state == .finished,
                   let ecc = set.eccentricDuration,
                   let con = set.concentricDuration,
                   ecc > 0 || con > 0 {
                    ExerciseTimingStore.shared.record(
                        id: set.id,
                        exerciseName: vm.exercise.name,
                        workoutName: self.name,
                        setNumber: index + 1,
                        weight: Double(set.weight) ?? 0,
                        reps: Int(set.reps) ?? 0,
                        eccentricDuration: ecc,
                        concentricDuration: con,
                        date: set.setFinished,
                        source: SetMotionTracker.shared.selectedSource.rawValue
                    )
                }
            }
        }
    }
    
    public func finishWorkout() {
        syncTimingsToStore()
        timerCancellable?.cancel()
    }
    
    var exerciseCountDetails: String {
        "\(self.exercises.count) Exercises, \(self.exercises.reduce(0) { $0 + $1.sets.count}) Sets"
    }
    
    var currentExercise: ExerciseViewModel? {
        guard exercises.indices.contains(currentExerciseIndex) else {
            return exercises.first
        }
        return exercises[currentExerciseIndex]
    }
    
    /// The exercise that is actively recording motion or the currently focused exercise.
    var activeOrCurrentExercise: ExerciseViewModel {
        if let activeID = motionTracker.activeSetID,
           let runningExercise = exercises.first(where: { vm in vm.sets.contains(where: { $0.id == activeID }) }) {
            return runningExercise
        }
        if let runningExercise = exercises.first(where: { vm in vm.sets.contains(where: { $0.state == .started }) }) {
            return runningExercise
        }
        return currentExercise ?? exercises.first ?? ExerciseViewModel(
            exercise: Exercise(name: "Exercise", equipmentName: "Equipment", demonstrationImage: .init("squat")),
            sets: []
        )
    }
    
    /// Returns the currently active set, or the next upcoming/last finished set for the active exercise.
    var activeOrLastSet: ExerciseSet? {
        if let activeID = motionTracker.activeSetID,
           let set = activeOrCurrentExercise.sets.first(where: { $0.id == activeID }) {
            return set
        }
        return activeOrCurrentExercise.activeOrCurrentSet
    }
    
    // MARK: - Timing & Durations
    
    var workoutElapsedTime: TimeInterval {
        guard let start = workoutStartDate else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }
    
    var workoutDurationString: String {
        formatDuration(workoutElapsedTime)
    }
    
    var setDurationString: String {
        guard let set = activeOrLastSet else {
            return "00:00"
        }
        
        switch set.state {
        case .started:
            let elapsed = max(0, now.timeIntervalSince(set.setStarted))
            return formatDuration(elapsed)
        case .finished:
            let elapsed = max(0, set.setFinished.timeIntervalSince(set.setStarted))
            return formatDuration(elapsed)
        case .notStarted:
            return "00:00"
        }
    }
    
    var stateSymbol: String {
        activeOrLastSet?.stateSymbol ?? activeOrCurrentExercise.stateSymbol
    }
    
    // MARK: - Actions
    
    func startWorkoutIfNeeded() {
        if workoutStartDate == nil {
            workoutStartDate = Date()
        }
        now = Date()
    }
    
    func cycleCurrentSetState() {
        activeOrCurrentExercise.cycleCurrentSetState()
        syncTimingsToStore(for: activeOrCurrentExercise)
    }
    
    func updateTime(to date: Date = Date()) {
        now = date
    }
    
    func startTimer() {
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] currentDate in
                self?.now = currentDate
            }
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
