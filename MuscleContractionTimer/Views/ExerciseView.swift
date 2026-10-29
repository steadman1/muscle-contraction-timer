//
//  ExerciseView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/14/26.
//

import SwiftUI

struct ExerciseView: View {
    @ObservedObject var viewModel: ExerciseViewModel
    @ObservedObject private var motionTracker = SetMotionTracker.shared
    @State private var showingProgression = false
    @State private var showingAlgorithmConfig = false
    
    var body: some View {
        VStack(spacing: Constants.Padding.m) {
            VStack(spacing: Constants.Padding.m) {
                HStack {
                    exerciseInfoTitle
                    
                    Spacer()
                    
                    exerciseInfoTitleButton(systemName: "stopwatch")
                    trackingOptionsEllipsisButton
                }
                
                VStack(spacing: Constants.Padding.s) {
                    ForEach(viewModel.sets.enumerated(), id: \.element.id) { index, set in
                        
                        ExerciseSetView(index, set) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.sets.removeAll { $0.id == set.id }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Constants.Padding.m)
            .background(
                RoundedRectangle(cornerRadius: Constants.Radius.l)
                    .fill(Color.background)
                    .strokeBorder(Color.stroke, lineWidth: Constants.strokeWidth)
            )
            .clipped()
            .compositingGroup()
            .shadow(color: Color.shadow, radius: 4, y: 4)
            
            HStack {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    showingProgression = true
                } label: {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text("Progression")
                    }
                    .font(Fonts.headline)
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity)
                }
                .sheet(isPresented: $showingProgression) {
                    ExerciseProgressionView(exerciseName: viewModel.exercise.name)
                }
                
                RoundedRectangle(cornerRadius: Constants.Radius.max)
                    .frame(width: Constants.strokeWidth, height: 24)
                    .foregroundStyle(Color.tertiaryText)
                
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    
                    viewModel.addSet()
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Set")
                    }
                    .font(Fonts.headline)
                    .foregroundStyle(Color.secondaryText)
                    .frame(maxWidth: .infinity)
                }
            }
            
            Spacer().frame(height: Constants.Padding.s)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.l)
                .fill(Color.background)
                .strokeBorder(Color.stroke, lineWidth: Constants.strokeWidth)
        )
        .compositingGroup()
        .shadow(color: Color.shadow, radius: 12)
        .shadow(color: Color.shadow, radius: 4)
        .sheet(isPresented: $showingAlgorithmConfig) {
            ExerciseMotionConfigSheet(viewModel: viewModel)
        }
        .onAppear {
            motionTracker.phaseOrder = viewModel.exercise.phaseOrder
            viewModel.propagateExerciseConfigurationToSets()
        }
    }
    
    var exerciseInfoTitle: some View {
        Group {
            viewModel.exercise.demonstrationImage
                .resizable()
                .frame(width: 40, height: 40) // images are squares
                .padding(Constants.Padding.xs)
                .background(Color.white) // image bgs are white
                .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.m))
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Radius.m)
                        .strokeBorder(Color.border, lineWidth: Constants.strokeWidth)
                )
            
            VStack(alignment: .leading) {
                Text(viewModel.exercise.name)
                    .foregroundStyle(Color.primaryText)
                    .font(Fonts.headline)
                HStack(spacing: Constants.Padding.xs) {
                    Group {
                        Image(systemName: motionTracker.selectedSource == .airPods ? "airpodspro" : "iphone")
                        Text(viewModel.exercise.equipmentName)
                        Text(" • ")
                            .foregroundStyle(Color.tertiaryText)
                        Text("\(viewModel.sets.count) Sets")
                    }
                    .foregroundStyle(Color.secondaryText)
                    .font(Fonts.subheadline)
                }
            }
        }
    }
    
    private var trackingOptionsEllipsisButton: some View {
        Menu {
            Section("Motion Tracking Device") {
                Picker("Sensor Source", selection: Binding(
                    get: { motionTracker.selectedSource },
                    set: { newSource in
                        motionTracker.selectedSource = newSource
                        if newSource == .airPods {
                            AudioHandoffManager.shared.triggerAirPodsHandoff()
                        }
                    }
                )) {
                    Label("iPhone", systemImage: "iphone")
                        .tag(SensorSource.iPhone)
                    
                    Label("AirPods", systemImage: "airpodspro")
                        .tag(SensorSource.airPods)
                }
                .pickerStyle(.inline)
            }
            
            if motionTracker.selectedSource == .airPods {
                Section {
                    Button {
                        AudioHandoffManager.shared.triggerAirPodsHandoff()
                    } label: {
                        Label("Nudge AirPods Connection", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            
            Section("Contraction Phase Order") {
                Picker("Phase Order", selection: Binding(
                    get: { viewModel.exercise.phaseOrder },
                    set: { newOrder in
                        viewModel.exercise.phaseOrder = newOrder
                        motionTracker.phaseOrder = newOrder
                        viewModel.propagateExerciseConfigurationToSets()
                    }
                )) {
                    ForEach(ExercisePhaseOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.inline)
            }
            
            Section("Algorithm Optimization") {
                Button {
                    showingAlgorithmConfig = true
                } label: {
                    Label("Motion Algorithm Config", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            exerciseInfoTitleButton(systemName: "ellipsis")
        }
        .buttonStyle(.plain)
    }
    
    // return styled button from sf symbol name
    func exerciseInfoTitleButton(systemName: String) -> some View {
        Group {
            Image(systemName: systemName)
                .font(Fonts.headline)
                .foregroundStyle(Color.secondaryText)
        }
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Radius.m)
                .strokeBorder(Color.border, lineWidth: Constants.strokeWidth)
        )
    }
}

struct ExerciseCard<Content: View>: View {
    let content: Content
    
    init(content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack {
            content
        }
        .frame(maxWidth: .infinity)
        .padding(Constants.Padding.m)
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.l)
                .fill(Color.background)
                .strokeBorder(Color.stroke, lineWidth: Constants.strokeWidth)
        )
        .compositingGroup()
        .shadow(color: Color.shadow, radius: 12)
        .shadow(color: Color.shadow, radius: 4)
    }
}

#Preview {
    let squatExercise = Exercise(name: "Back Squat", equipmentName: "Barbell", demonstrationImage: .init("squat"))
    
    VStack {
        ExerciseView(
            viewModel: .init(
                exercise: squatExercise,
                sets: [
                    .init(weight: 135, reps: 8),
                    .init(weight: 135, reps: 7),
                    .init(weight: 135, reps: 6)
                ]
            )
        )
    }
    .frame(height: 500)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(Constants.Padding.l)
    .background(Color.background)
}
