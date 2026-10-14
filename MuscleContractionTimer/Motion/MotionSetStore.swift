//
//  MotionSetStore.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/13/26.
//

import Foundation
import Combine
import SwiftUI

@MainActor
public final class MotionSetStore: ObservableObject {
    @Published public private(set) var savedSets: [PersistedMotionSet] = []
    
    private let directoryURL: URL
    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()
    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()
    
    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.directoryURL = docs.appendingPathComponent("SavedMotionSets", isDirectory: true)
        createDirectoryIfNeeded()
        loadAllSets()
    }
    
    private func createDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
    
    public func loadAllSets() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else { return }
        
        var loaded: [PersistedMotionSet] = []
        for url in urls where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let set = try? decoder.decode(PersistedMotionSet.self, from: data) {
                loaded.append(set)
            }
        }
        
        self.savedSets = loaded.sorted { $0.createdAt > $1.createdAt }
    }
    
    public func save(_ set: PersistedMotionSet) {
        let fileURL = directoryURL.appendingPathComponent("\(set.id.uuidString).json")
        do {
            let data = try encoder.encode(set)
            try data.write(to: fileURL, options: .atomic)
            if let idx = savedSets.firstIndex(where: { $0.id == set.id }) {
                savedSets[idx] = set
            } else {
                savedSets.insert(set, at: 0)
            }
        } catch {
            print("Failed to persist motion set: \(error.localizedDescription)")
        }
    }
    
    public func delete(_ set: PersistedMotionSet) {
        let fileURL = directoryURL.appendingPathComponent("\(set.id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        savedSets.removeAll { $0.id == set.id }
    }
    
    public func delete(at offsets: IndexSet) {
        for index in offsets {
            let set = savedSets[index]
            let fileURL = directoryURL.appendingPathComponent("\(set.id.uuidString).json")
            try? FileManager.default.removeItem(at: fileURL)
        }
        savedSets.remove(atOffsets: offsets)
    }
}
