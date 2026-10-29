//
//  ExerciseMotionConfigSheet.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/24/26.
//

import SwiftUI

struct ExerciseMotionConfigSheet: View {
    @ObservedObject var viewModel: ExerciseViewModel
    @ObservedObject private var motionTracker = SetMotionTracker.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var phaseOrder: ExercisePhaseOrder
    @State private var currentConfig: AnalyzerConfiguration
    @State private var selectedSourceTab: SensorSource
    
    init(viewModel: ExerciseViewModel) {
        self.viewModel = viewModel
        let source = SetMotionTracker.shared.selectedSource
        self._phaseOrder = State(initialValue: viewModel.exercise.phaseOrder)
        self._selectedSourceTab = State(initialValue: source)
        self._currentConfig = State(initialValue: viewModel.exercise.configuration(for: source))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    exerciseSummaryHeader
                    
                    profileQuickSelectSection
                    
                    biomechanicalRationaleCard
                    
                    parameterTuningCard
                }
                .padding()
            }
            .background(Color.background)
            .navigationTitle("Algorithm Config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAndApply()
                        dismiss()
                    }
                    .font(Fonts.headline)
                    .foregroundStyle(Color.orange)
                }
            }
        }
    }
    
    // MARK: - Exercise Summary Header
    
    private var exerciseSummaryHeader: some View {
        HStack(spacing: 14) {
            viewModel.exercise.demonstrationImage
                .resizable()
                .frame(width: 44, height: 44)
                .padding(4)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.m))
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Radius.m)
                        .strokeBorder(Color.border, lineWidth: Constants.strokeWidth)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.exercise.name)
                    .font(Fonts.headline)
                    .foregroundStyle(Color.primaryText)
                
                Text("Optimized for theoretical overlap with real-world reps")
                    .font(Fonts.subheadline)
                    .foregroundStyle(Color.secondaryText)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.l)
                .fill(Color.foreground)
                .strokeBorder(Color.stroke, lineWidth: Constants.strokeWidth)
        )
    }
    
    // MARK: - Quick Profile Presets
    
    private var profileQuickSelectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BIOMECHANICAL MOTION PROFILE")
                .font(.caption.bold())
                .foregroundStyle(Color.tertiaryText)
            
            HStack(spacing: 10) {
                presetButton(
                    title: "Back Squats",
                    subtitle: "Eccentric 1st • 2.8% Onset",
                    icon: "figure.strengthtraining.traditional",
                    isSelected: isSquatMatching
                ) {
                    applySquatPreset()
                }
                
                presetButton(
                    title: "Pull Ups",
                    subtitle: "Concentric 1st • 2.0% Onset",
                    icon: "figure.pull.up",
                    isSelected: isPullUpMatching
                ) {
                    applyPullUpPreset()
                }
            }
            
            // Phase Order Segmented Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Phase Sequence")
                    .font(Fonts.subheadline)
                    .foregroundStyle(Color.secondaryText)
                
                Picker("Phase Order", selection: $phaseOrder) {
                    ForEach(ExercisePhaseOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.l)
                .fill(Color.foreground)
                .strokeBorder(Color.stroke, lineWidth: Constants.strokeWidth)
        )
    }
    
    private func presetButton(
        title: String,
        subtitle: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon)
                        .font(Fonts.headline)
                        .foregroundStyle(isSelected ? Color.orange : Color.secondaryText)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                    }
                }
                
                Text(title)
                    .font(Fonts.headline)
                    .foregroundStyle(Color.primaryText)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Constants.Radius.m)
                    .fill(isSelected ? Color.orange.opacity(0.12) : Color.background)
                    .strokeBorder(isSelected ? Color.orange : Color.border, lineWidth: isSelected ? 1.5 : Constants.strokeWidth)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Biomechanical Rationale Card
    
    private var biomechanicalRationaleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Theoretical Overlap Optimization", systemImage: "sparkles")
                .font(.caption.bold())
                .foregroundStyle(Color.orange)
            
            if phaseOrder == .eccentricFirst {
                Text("• Squat Kinematics: Starts with eccentric descent from standing lockout. A 2.8% departure ratio eliminates standing postural sway while detecting immediate knee break within 1-2 frames. Edge exclusion at 16% suppresses walkout and rack shocks.")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            } else {
                Text("• Pull-Up Kinematics: Starts from a dead hang with upward concentric pull. A 2.0% departure ratio catches instant lat recruitment from dead stop for maximum IoU with visual rep start. Edge exclusion at 18% rejects initial jump-to-bar and floor drop shock.")
                    .font(.caption)
                    .foregroundStyle(Color.secondaryText)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.l)
                .fill(Color.orange.opacity(0.06))
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: Constants.strokeWidth)
        )
    }
    
    // MARK: - Parameter Tuning Card
    
    private var parameterTuningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("ALGORITHM HYPERPARAMETERS")
                    .font(.caption.bold())
                    .foregroundStyle(Color.tertiaryText)
                
                Spacer()
                
                Picker("Sensor Source", selection: $selectedSourceTab) {
                    Text("iPhone").tag(SensorSource.iPhone)
                    Text("AirPods").tag(SensorSource.airPods)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .onChange(of: selectedSourceTab) { _, newSource in
                    currentConfig = viewModel.exercise.configuration(for: newSource)
                }
            }
            
            // Crest Departure Ratio
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Onset Departure Sensitivity")
                        .font(Fonts.subheadline)
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    Text(String(format: "%.1f%% ROM", currentConfig.crestDepartureRatio * 100))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Color.orange)
                }
                Text("Threshold above resting trough defining rep start/end. Lower = tighter start capture.")
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                Slider(value: $currentConfig.crestDepartureRatio, in: 0.01...0.10, step: 0.002)
                    .tint(Color.orange)
            }
            
            Divider().background(Color.stroke)
            
            // Edge Exclusion Ratio
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Edge Exclusion Taper")
                        .font(Fonts.subheadline)
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    Text(String(format: "%.0f%% Edge", currentConfig.edgeExclusionRatio * 100))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Color.orange)
                }
                Text("Penalizes setup steps (walkout/jump to bar) and rerack/drop impact spikes.")
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                Slider(value: $currentConfig.edgeExclusionRatio, in: 0.04...0.30, step: 0.02)
                    .tint(Color.orange)
            }
            
            Divider().background(Color.stroke)
            
            // High-Pass Cutoff
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("High-Pass Drift Filter")
                        .font(Fonts.subheadline)
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    Text(String(format: "%.2f Hz", currentConfig.highPassCutoffHz))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Color.orange)
                }
                Text("Removes sensor baseline drift while keeping slow 3-4s eccentric descents intact.")
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                Slider(value: $currentConfig.highPassCutoffHz, in: 0.03...0.25, step: 0.01)
                    .tint(Color.orange)
            }
            
            Divider().background(Color.stroke)
            
            // Low-Pass Cutoff
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Low-Pass Denoise Filter")
                        .font(Fonts.subheadline)
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    Text(String(format: "%.1f Hz", currentConfig.lowPassCutoffHz))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Color.orange)
                }
                Text("Filters high-frequency barbell vibration and head tremor without lagging peaks.")
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                Slider(value: $currentConfig.lowPassCutoffHz, in: 1.5...10.0, step: 0.2)
                    .tint(Color.orange)
            }
            
            Divider().background(Color.stroke)
            
            // Velocity Threshold Ratio
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Inflection Velocity Gate")
                        .font(Fonts.subheadline)
                        .foregroundStyle(Color.primaryText)
                    Spacer()
                    Text(String(format: "%.1f%% Peak", currentConfig.velocityThresholdRatio * 100))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Color.orange)
                }
                Text("Fraction of peak velocity required to confirm active repetition inflection.")
                    .font(.caption2)
                    .foregroundStyle(Color.secondaryText)
                Slider(value: $currentConfig.velocityThresholdRatio, in: 0.01...0.12, step: 0.01)
                    .tint(Color.orange)
            }
            
            HStack {
                Button("Reset to Default") {
                    let defaultPreset = ExerciseMotionConfiguration.preset(for: viewModel.exercise.name)
                    phaseOrder = defaultPreset.defaultPhaseOrder
                    currentConfig = defaultPreset.configuration(for: selectedSourceTab)
                }
                .font(.caption.bold())
                .foregroundStyle(Color.secondaryText)
                
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.l)
                .fill(Color.foreground)
                .strokeBorder(Color.stroke, lineWidth: Constants.strokeWidth)
        )
    }
    
    // MARK: - Helpers
    
    private var isSquatMatching: Bool {
        phaseOrder == .eccentricFirst && abs(currentConfig.crestDepartureRatio - 0.028) < 0.005
    }
    
    private var isPullUpMatching: Bool {
        phaseOrder == .concentricFirst && abs(currentConfig.crestDepartureRatio - 0.020) < 0.005
    }
    
    private func applySquatPreset() {
        phaseOrder = .eccentricFirst
        currentConfig = AnalyzerConfiguration.squatPreset(for: selectedSourceTab)
        viewModel.exercise.motionConfiguration = .squat
    }
    
    private func applyPullUpPreset() {
        phaseOrder = .concentricFirst
        currentConfig = AnalyzerConfiguration.pullUpPreset(for: selectedSourceTab)
        viewModel.exercise.motionConfiguration = .pullUp
    }
    
    private func saveAndApply() {
        viewModel.exercise.phaseOrder = phaseOrder
        viewModel.exercise.motionConfiguration.updateConfiguration(currentConfig, for: selectedSourceTab)
        motionTracker.phaseOrder = phaseOrder
        viewModel.propagateExerciseConfigurationToSets()
        
        // Re-analyze any completed sets with the updated configuration
        for set in viewModel.sets where set.state == .finished {
            set.recomputeTimings()
        }
    }
}
