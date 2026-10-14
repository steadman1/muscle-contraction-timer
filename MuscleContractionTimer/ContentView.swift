//
//  ContentView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/5/26.
//

import SwiftUI

public struct ContentView: View {
    @StateObject private var controller = MotionSessionController()
    @StateObject private var store = MotionSetStore()
    
    public init() {}
    
    public var body: some View {
        TabView {
            RecorderTabView(controller: controller, store: store)
                .tabItem {
                    Label("Recorder", systemImage: "waveform.path.ecg")
                }
            
            SavedSetsTabView(store: store)
                .tabItem {
                    Label("Test Bench", systemImage: "tray.full.fill")
                }
                .badge(store.savedSets.count)
        }
    }
}

public struct RecorderTabView: View {
    @ObservedObject var controller: MotionSessionController
    @ObservedObject var store: MotionSetStore
    @State private var customSetTitle: String = ""
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    configurationHeader
                    workflowCard
                    
                    if let result = controller.analysisResult {
                        AnalysisReportView(result: result)
                    }
                }
                .padding()
            }
            .navigationTitle("Contraction Timer")
        }
    }
    
    // MARK: - Configuration Header
    
    private var configurationHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Picker("Sensor Source", selection: Binding(
                    get: { controller.selectedSource },
                    set: { controller.switchSource(to: $0) }
                )) {
                    ForEach(SensorSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                
                if controller.selectedSource == .airPods {
                    Button("Nudge") {
                        AudioHandoffManager.shared.triggerAirPodsHandoff()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    AudioRoutePicker()
                        .frame(width: 28, height: 28)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Exercise Phase Sequence")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Phase Order", selection: $controller.phaseOrder) {
                    ForEach(ExercisePhaseOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
    
    // MARK: - Recording & Persistence Controls
    
    private var workflowCard: some View {
        let p1Name = controller.phaseOrder.firstPhase.rawValue
        let p2Name = controller.phaseOrder.secondPhase.rawValue
        
        return VStack(spacing: 14) {
            switch controller.state {
            case .idle:
                Text("Sequence: \(p1Name) → Isometric Hold → \(p2Name)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button {
                    customSetTitle = ""
                    controller.startRecording()
                } label: {
                    Label("Start Set Recording", systemImage: "record.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
            case .recording(let frames, let elapsed):
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text(String(format: "Recording: %.1f s (%d frames)", elapsed, frames))
                        .font(.headline.monospacedDigit())
                }
                
                VStack(spacing: 10) {
                    HStack {
                        Text("Manual Ground-Truth Marker")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Completed Reps: \(controller.manualGroundTruthReps.count)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundColor(.purple)
                    }
                    
                    manualPhaseControls(p1Name: p1Name, p2Name: p2Name)
                }
                .padding(12)
                .background(Color(uiColor: .tertiarySystemBackground))
                .cornerRadius(10)
                
                Button {
                    controller.stopRecording()
                } label: {
                    Label("Stop Set Recording", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                
            case .awaitingRepCount(let duration):
                Text(String(format: "Captured %.1f s (%d manual ground-truth reps logged).", duration, controller.manualGroundTruthReps.count))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Confirm total repetitions performed:")
                    .font(.headline)
                
                Stepper(value: $controller.userEnteredRepCount, in: 1...100) {
                    HStack {
                        Text("Completed Reps:")
                        Spacer()
                        Text("\(controller.userEnteredRepCount)")
                            .font(.title2.bold().monospacedDigit())
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 8)
                
                Button {
                    controller.computeTimingsForRepCount()
                } label: {
                    Label("Calculate Timings & Accuracy", systemImage: "waveform.badge.magnifyingglass")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                
            case .analyzing:
                ProgressView("Segmenting \(controller.userEnteredRepCount) repetitions...")
                    .padding()
                
            case .completed:
                Stepper(
                    "Target Reps: \(controller.userEnteredRepCount)",
                    value: $controller.userEnteredRepCount,
                    in: 1...100
                )
                .font(.subheadline.bold())
                .onChange(of: controller.userEnteredRepCount) { _ in
                    controller.computeTimingsForRepCount()
                }
                
                Divider()
                
                // Persist Set Section
                if controller.hasSavedCurrentSet {
                    Label("Saved to Test Bench", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.green)
                } else {
                    HStack(spacing: 8) {
                        TextField("Set name (e.g., Paused Squat 10 Reps)", text: $customSetTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                        
                        Button {
                            controller.saveCurrentSet(title: customSetTitle, to: store)
                        } label: {
                            Label("Save Set", systemImage: "square.and.arrow.down")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                }
                
                Button {
                    customSetTitle = ""
                    controller.startRecording()
                } label: {
                    Label("Record New Set", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
            case .error(let msg):
                Text(msg)
                    .font(.subheadline)
                    .foregroundColor(.red)
                Button("Start Over") {
                    controller.startRecording()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private func manualPhaseControls(p1Name: String, p2Name: String) -> some View {
        switch controller.manualCaptureState {
        case .idle:
            Button {
                controller.startManualPhase1()
            } label: {
                Label("Start \(p1Name)", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            
            Text("Idle between reps — Tap to begin Rep #\(controller.manualGroundTruthReps.count + 1) (\(p1Name))")
                .font(.caption2)
                .foregroundColor(.secondary)
            
        case .inFirstPhase(let startTime):
            VStack(spacing: 8) {
                Button {
                    controller.stopManualPhase1EnterIsometric()
                } label: {
                    Label("Stop \(p1Name) (Enter Isometric Hold)", systemImage: "pause.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                
                Button {
                    controller.transitionDirectlyToPhase2()
                } label: {
                    Label("Instant Turnaround → Start \(p2Name) (0s Iso)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .tint(.blue)
            }
            
            Text(String(format: "Active: %@ phase (started at %.2fs)...", p1Name, startTime))
                .font(.caption.monospacedDigit())
                .foregroundColor(.orange)
            
        case .inIsometricPause(let startTime, let p1EndTime):
            Button {
                controller.startManualPhase2FromIsometric()
            } label: {
                Label("Start \(p2Name) (End Isometric)", systemImage: "bolt.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            
            Text(String(format: "%@: %.2fs | Holding Isometric since %.2fs...", p1Name, p1EndTime - startTime, p1EndTime))
                .font(.caption.monospacedDigit())
                .foregroundColor(.blue)
            
        case .inSecondPhase(let startTime, let p1EndTime, let p2StartTime):
            Button {
                controller.endManualPhase2()
            } label: {
                Label("End \(p2Name) (Complete Rep)", systemImage: "flag.checkered")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            
            Text(String(format: "%@: %.2fs | Iso: %.2fs | Active: %@...", p1Name, p1EndTime - startTime, p2StartTime - p1EndTime, p2Name))
                .font(.caption.monospacedDigit())
                .foregroundColor(.purple)
        }
    }
}
