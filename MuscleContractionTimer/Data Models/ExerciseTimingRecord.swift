//
//  ExerciseTimingRecord.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/26/26.
//

import Foundation

/// A persistent record of concentric and eccentric contraction timings for a single exercise set within a workout.
public struct ExerciseTimingRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let exerciseName: String
    public let workoutName: String
    public let setNumber: Int
    public let weight: Double
    public let reps: Int
    public let eccentricDuration: TimeInterval
    public let concentricDuration: TimeInterval
    public let date: Date
    public let source: String
    
    public var totalDuration: TimeInterval {
        eccentricDuration + concentricDuration
    }
    
    /// Ratio of eccentric to concentric duration (e.g. 3.0 means 3x longer eccentric phase).
    public var tempoRatio: Double {
        guard concentricDuration > 0 else { return 0 }
        return eccentricDuration / concentricDuration
    }
    
    public var formattedEccentric: String {
        String(format: "%.2fs", eccentricDuration)
    }
    
    public var formattedConcentric: String {
        String(format: "%.2fs", concentricDuration)
    }
    
    public var formattedTotal: String {
        String(format: "%.2fs", totalDuration)
    }
    
    public init(
        id: UUID = UUID(),
        exerciseName: String,
        workoutName: String,
        setNumber: Int,
        weight: Double,
        reps: Int,
        eccentricDuration: TimeInterval,
        concentricDuration: TimeInterval,
        date: Date = Date(),
        source: String = "iPhone"
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.workoutName = workoutName
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.eccentricDuration = eccentricDuration
        self.concentricDuration = concentricDuration
        self.date = date
        self.source = source
    }
}

/// A grouped collection of timing records representing a single workout session for an exercise.
public struct WorkoutTimingGroup: Identifiable {
    public var id: String {
        "\(workoutName)_\(date.timeIntervalSince1970)"
    }
    public let workoutName: String
    public let date: Date
    public let records: [ExerciseTimingRecord]
    
    public var dateFormatted: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
    
    public var dateOnlyFormatted: String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
    
    public var averageEccentric: TimeInterval {
        let valid = records.filter { $0.eccentricDuration > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0.0) { $0 + $1.eccentricDuration } / Double(valid.count)
    }
    
    public var averageConcentric: TimeInterval {
        let valid = records.filter { $0.concentricDuration > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0.0) { $0 + $1.concentricDuration } / Double(valid.count)
    }
    
    public var averageTotal: TimeInterval {
        averageEccentric + averageConcentric
    }
    
    public var averageTempoRatio: Double {
        guard averageConcentric > 0 else { return 0 }
        return averageEccentric / averageConcentric
    }
    
    public var maxWeight: Double {
        records.map(\.weight).max() ?? 0
    }
    
    public var totalReps: Int {
        records.reduce(0) { $0 + $1.reps }
    }
}
