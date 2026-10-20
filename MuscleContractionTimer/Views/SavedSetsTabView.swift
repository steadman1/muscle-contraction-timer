//
//  SavedSetsTabView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/13/26.
//

import SwiftUI

public struct SavedSetsTabView: View {
    @ObservedObject var store: MotionSetStore
    @State private var batchSummary: (eccMAE: Double, conMAE: Double, turnMAE: Double, iou: Double)?
    @State private var isRunningBatch = false
    
    public init(store: MotionSetStore) {
        self.store = store
    }
    
    public var body: some View {
        NavigationStack {
            List {
                if !store.savedSets.isEmpty {
                    Section("Global Algorithm Benchmark") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Evaluate current OfflineCycleAnalyzer code across all \(store.savedSets.count) saved datasets.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let summary = batchSummary {
                                HStack {
                                    benchmarkStat(label: "Ecc MAE", value: String(format: "%.2fs", summary.eccMAE))
                                    Spacer()
                                    benchmarkStat(label: "Con MAE", value: String(format: "%.2fs", summary.conMAE))
                                    Spacer()
                                    benchmarkStat(label: "Turn MAE", value: String(format: "%.2fs", summary.turnMAE))
                                    Spacer()
                                    benchmarkStat(label: "Mean IoU", value: String(format: "%.0f%%", summary.iou * 100))
                                }
                                .padding(.vertical, 4)
                            }
                            
                            Button {
                                runGlobalBenchmark()
                            } label: {
                                if isRunningBatch {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label("Run Benchmark on All Saved Sets", systemImage: "gauge.with.dots.needle.67percent")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunningBatch)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("Persisted Motion Sets (\(store.savedSets.count))") {
                    if store.savedSets.isEmpty {
                        Text("No saved sets yet. Record a set in the Recorder tab and tap 'Save Set'.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(store.savedSets) { set in
                            NavigationLink(value: set.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(set.title)
                                            .font(.headline)
                                        Spacer()
                                        Text(set.source.rawValue)
                                            .font(.caption.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15))
                                            .foregroundColor(.blue)
                                            .cornerRadius(4)
                                    }
                                    
                                    HStack(spacing: 12) {
                                        Text("\(set.targetRepCount) reps")
                                        Text("•")
                                        Text("\(set.groundTruthReps.count) GT marked")
                                        Text("•")
                                        Text(String(format: "%.1fs (%d frames)", set.duration, set.frames.count))
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    
                                    Text(set.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete(perform: store.delete)
                    }
                }
            }
            .navigationTitle("Test Bench")
            .navigationDestination(for: UUID.self) { setID in
                if let selectedSet = store.savedSets.first(where: { $0.id == setID }) {
                    SavedSetDetailView(set: selectedSet, store: store)
                } else {
                    Text("Dataset not found.")
                }
            }
            .toolbar {
                if !store.savedSets.isEmpty {
                    EditButton()
                }
            }
        }
    }
    
    private func benchmarkStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
        }
    }
    
    private func runGlobalBenchmark() {
        let setsSnapshot = store.savedSets
        guard !setsSnapshot.isEmpty else { return }
        isRunningBatch = true
        
        Task.detached(priority: .userInitiated) {
            var eccErrors: [Double] = []
            var conErrors: [Double] = []
            var turnErrors: [Double] = []
            var ious: [Double] = []
            
            for set in setsSnapshot {
                let base = OfflineCycleAnalyzer.analyze(
                    frames: set.frames,
                    targetRepCount: set.targetRepCount,
                    source: set.source,
                    phaseOrder: set.phaseOrder
                )
                let enriched = SessionAnalysisResult(
                    source: set.source,
                    phaseOrder: set.phaseOrder,
                    principalAxis: base.principalAxis,
                    explainedVarianceRatio: base.explainedVarianceRatio,
                    samples: base.samples,
                    cycles: base.cycles,
                    groundTruthReps: set.groundTruthReps
                )
                if let e = enriched.meanAbsoluteEccentricError { eccErrors.append(e) }
                if let c = enriched.meanAbsoluteConcentricError { conErrors.append(c) }
                if let t = enriched.meanAbsoluteTurnaroundError { turnErrors.append(t) }
                if let u = enriched.meanIoU { ious.append(u) }
            }
            
            let avgEcc = eccErrors.isEmpty ? 0 : eccErrors.reduce(0, +) / Double(eccErrors.count)
            let avgCon = conErrors.isEmpty ? 0 : conErrors.reduce(0, +) / Double(conErrors.count)
            let avgTurn = turnErrors.isEmpty ? 0 : turnErrors.reduce(0, +) / Double(turnErrors.count)
            let avgIoU = ious.isEmpty ? 0 : ious.reduce(0, +) / Double(ious.count)
            
            await MainActor.run {
                self.batchSummary = (avgEcc, avgCon, avgTurn, avgIoU)
                self.isRunningBatch = false
            }
        }
    }
}

// MARK: - Detail View & Live Hyperparameter Sandbox

public struct SavedSetDetailView: View {
    let set: PersistedMotionSet
    @ObservedObject var store: MotionSetStore
    
    @State private var phaseOrder: ExercisePhaseOrder
    @State private var targetRepCount: Int
    @State private var config: AnalyzerConfiguration
    @State private var analysisResult: SessionAnalysisResult?
    @State private var isAnalyzing = false
    @State private var showParameterTuning = true
    
    public init(set: PersistedMotionSet, store: MotionSetStore) {
        self.set = set
        self.store = store
        self._phaseOrder = State(initialValue: set.phaseOrder)
        self._targetRepCount = State(initialValue: set.targetRepCount)
        self._config = State(initialValue: .preset(for: set.source))
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                datasetControlsCard
                parameterSandboxCard
                
                if isAnalyzing {
                    ProgressView("Running OfflineCycleAnalyzer...")
                        .padding()
                } else if let result = analysisResult {
                    AnalysisReportView(result: result)
                }
            }
            .padding()
        }
        .navigationTitle(set.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: set.id) {
            runAnalysis()
        }
    }
    
    private var datasetControlsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Source: \(set.source.rawValue)")
                    .font(.caption.bold())
                Spacer()
                Text(String(format: "Duration: %.2fs (%d frames)", set.duration, set.frames.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Picker("Phase Order", selection: $phaseOrder) {
                ForEach(ExercisePhaseOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: phaseOrder) { _ in
                persistMetadataUpdate()
                runAnalysis()
            }
            
            Stepper("Target Reps: \(targetRepCount)", value: $targetRepCount, in: 1...100)
                .font(.subheadline.bold())
                .onChange(of: targetRepCount) { _ in
                    persistMetadataUpdate()
                    runAnalysis()
                }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var parameterSandboxCard: some View {
        DisclosureGroup("Algorithm Hyperparameter Sandbox", isExpanded: $showParameterTuning) {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Edge Exclusion Taper Ratio")
                        Spacer()
                        Text(String(format: "%.0f%%", config.edgeExclusionRatio * 100))
                            .monospacedDigit()
                    }
                    Slider(value: $config.edgeExclusionRatio, in: 0.0...0.30, step: 0.02) { editing in
                        if !editing { runAnalysis() }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Crest Departure Ratio")
                        Spacer()
                        Text(String(format: "%.2f", config.crestDepartureRatio))
                            .monospacedDigit()
                    }
                    Slider(value: $config.crestDepartureRatio, in: 0.01...0.15, step: 0.01) { editing in
                        if !editing { runAnalysis() }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("High-Pass Drift Cutoff")
                        Spacer()
                        Text(String(format: "%.2f Hz", config.highPassCutoffHz))
                            .monospacedDigit()
                    }
                    Slider(value: $config.highPassCutoffHz, in: 0.02...0.35, step: 0.02) { editing in
                        if !editing { runAnalysis() }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Low-Pass Denoise Cutoff")
                        Spacer()
                        Text(String(format: "%.1f Hz", config.lowPassCutoffHz))
                            .monospacedDigit()
                    }
                    Slider(value: $config.lowPassCutoffHz, in: 1.5...10.0, step: 0.5) { editing in
                        if !editing { runAnalysis() }
                    }
                }
                
                Button("Reset to \(set.source.rawValue) Preset") {
                    config = .preset(for: set.source)
                    runAnalysis()
                }
                .font(.caption.bold())
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
            .font(.caption)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func persistMetadataUpdate() {
        var updated = set
        updated.phaseOrder = phaseOrder
        updated.targetRepCount = targetRepCount
        store.save(updated)
    }
    
    private func runAnalysis() {
        isAnalyzing = true
        let framesSnapshot = set.frames
        let sourceSnapshot = set.source
        let gtSnapshot = set.groundTruthReps
        let orderSnapshot = phaseOrder
        let repsSnapshot = targetRepCount
        let configSnapshot = config
        
        Task.detached(priority: .userInitiated) {
            let base = OfflineCycleAnalyzer.analyze(
                frames: framesSnapshot,
                targetRepCount: repsSnapshot,
                source: sourceSnapshot,
                configuration: configSnapshot,
                phaseOrder: orderSnapshot
            )
            let enriched = SessionAnalysisResult(
                source: sourceSnapshot,
                phaseOrder: orderSnapshot,
                principalAxis: base.principalAxis,
                explainedVarianceRatio: base.explainedVarianceRatio,
                samples: base.samples,
                cycles: base.cycles,
                groundTruthReps: gtSnapshot
            )
            await MainActor.run {
                self.analysisResult = enriched
                self.isAnalyzing = false
            }
        }
    }
}
