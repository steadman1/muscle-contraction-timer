//
//  ExerciseTimingStore.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/26/26.
//

import Foundation
import Combine
import SwiftUI

/// Persistent store that tracks and persists concentric and eccentric timings across workouts per exercise.
@MainActor
public final class ExerciseTimingStore: ObservableObject {
    public static let shared = ExerciseTimingStore()
    
    @Published public private(set) var records: [ExerciseTimingRecord] = []
    
    private let directoryURL: URL
    private let fileURL: URL
    
    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()
    
    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()
    
    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        self.directoryURL = docs.appendingPathComponent("ExerciseTimings", isDirectory: true)
        self.fileURL = directoryURL.appendingPathComponent("timings_history.json")
        
        createDirectoryIfNeeded()
        loadRecords()
    }
    
    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
    
    public func loadRecords() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let loaded = try? decoder.decode([ExerciseTimingRecord].self, from: data) else {
            return
        }
        self.records = loaded.sorted { $0.date > $1.date }
    }
    
    private func saveToDisk() {
        createDirectoryIfNeeded()
        do {
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to persist exercise timings: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Recording API
    
    public func record(
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
        guard eccentricDuration > 0 || concentricDuration > 0 else { return }
        
        let newRecord = ExerciseTimingRecord(
            id: id,
            exerciseName: exerciseName,
            workoutName: workoutName,
            setNumber: setNumber,
            weight: weight,
            reps: reps,
            eccentricDuration: eccentricDuration,
            concentricDuration: concentricDuration,
            date: date,
            source: source
        )
        
        if let existingIndex = records.firstIndex(where: { $0.id == id }) {
            records[existingIndex] = newRecord
        } else {
            records.insert(newRecord, at: 0)
        }
        
        records.sort { $0.date > $1.date }
        saveToDisk()
    }
    
    // MARK: - Querying & Aggregation
    
    public func records(for exerciseName: String) -> [ExerciseTimingRecord] {
        records.filter { $0.exerciseName.caseInsensitiveCompare(exerciseName) == .orderedSame }
    }
    
    public func distinctExerciseNames() -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for r in records {
            let key = r.exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                names.append(r.exerciseName)
            }
        }
        return names.sorted()
    }
    
    public func averageEccentric(for exerciseName: String) -> TimeInterval? {
        let matching = records(for: exerciseName).filter { $0.eccentricDuration > 0 }
        guard !matching.isEmpty else { return nil }
        return matching.reduce(0.0) { $0 + $1.eccentricDuration } / Double(matching.count)
    }
    
    public func averageConcentric(for exerciseName: String) -> TimeInterval? {
        let matching = records(for: exerciseName).filter { $0.concentricDuration > 0 }
        guard !matching.isEmpty else { return nil }
        return matching.reduce(0.0) { $0 + $1.concentricDuration } / Double(matching.count)
    }
    
    public func latestRecord(for exerciseName: String) -> ExerciseTimingRecord? {
        records(for: exerciseName).first
    }
    
    /// Groups records for a specific exercise into distinct workout sessions sorted reverse-chronologically.
    public func workoutGroups(for exerciseName: String) -> [WorkoutTimingGroup] {
        let exerciseRecords = records(for: exerciseName)
        let calendar = Calendar.current
        
        // Group by workoutName and same calendar day
        var grouped: [String: (workoutName: String, date: Date, records: [ExerciseTimingRecord])] = [:]
        
        for record in exerciseRecords {
            let components = calendar.dateComponents([.year, .month, .day], from: record.date)
            let key = "\(record.workoutName.lowercased())_\(components.year ?? 0)_\(components.month ?? 0)_\(components.day ?? 0)"
            
            if var entry = grouped[key] {
                entry.records.append(record)
                if record.date > entry.date {
                    entry.date = record.date
                }
                grouped[key] = entry
            } else {
                grouped[key] = (record.workoutName, record.date, [record])
            }
        }
        
        let groups = grouped.values.map { entry in
            WorkoutTimingGroup(
                workoutName: entry.workoutName,
                date: entry.date,
                records: entry.records.sorted { $0.setNumber < $1.setNumber }
            )
        }
        
        return groups.sorted { $0.date > $1.date }
    }
    
    // MARK: - Deletion
    
    public func delete(recordID: UUID) {
        records.removeAll { $0.id == recordID }
        saveToDisk()
    }
    
    public func delete(at offsets: IndexSet, for exerciseName: String) {
        let targetRecords = records(for: exerciseName)
        let idsToDelete = offsets.map { targetRecords[$0].id }
        records.removeAll { idsToDelete.contains($0.id) }
        saveToDisk()
    }
    
    public func clearAll() {
        records.removeAll()
        saveToDisk()
    }
}
