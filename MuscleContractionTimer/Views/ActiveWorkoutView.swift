//
//  ActiveWorkoutView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/22/26.
//

import SwiftUI

fileprivate let bottomBarHeight: CGFloat = 64

struct ActiveWorkoutView: View {
    
    @StateObject private var workoutViewModel = WorkoutViewModel(exercises: WorkoutViewModel.defaultExercises())
    
    var body: some View {
        ScrollView {
            VStack(spacing: Constants.Padding.m) {
                ForEach(workoutViewModel.exercises) { exerciseVM in
                    ExerciseView(viewModel: exerciseVM)
                }
            }
            .padding(Constants.Padding.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.background)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top) {
            HeaderView(timeString: workoutViewModel.workoutDurationString)
                .padding(.horizontal, Constants.Padding.m)
        }
        .safeAreaInset(edge: .bottom) {
            FooterView(
                viewModel: workoutViewModel.activeOrCurrentExercise,
                setDurationString: workoutViewModel.setDurationString,
                heartRate: workoutViewModel.heartRateString
            ) {
                workoutViewModel.cycleCurrentSetState()
            }
            .padding(.horizontal, Constants.Padding.m)
        }
        .onAppear {
            workoutViewModel.startWorkoutIfNeeded()
        }
    }
}

struct HeaderView: View {
    var timeString: String = "00:00"
    
    var body: some View {
        HStack {
            Text(timeString)
                .font(Fonts.title)
                .monospacedDigit()
            Spacer()
            Button(action: {}) {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.glass)
            .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.max))
        }
        .background(.ultraThinMaterial)
    }
}

struct FooterView: View {
    @ObservedObject var viewModel: ExerciseViewModel
    var setDurationString: String
    var heartRate: String = "—"
    var onActionTap: (() -> Void)? = nil
    
    var activeOrCurrentSet: ExerciseSet? {
        viewModel.activeOrCurrentSet
    }
    
    var stateSymbol: String {
        activeOrCurrentSet?.stateSymbol ?? viewModel.stateSymbol
    }
    
    var body: some View {
        ZStack {
            Color.orange.opacity(0.95)
                .frame(height: bottomBarHeight)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.max))
                .blur(radius: 90)
            
            HStack {
                Group {
                    HStack {
                        VStack(
                            alignment: .leading,
                            spacing: Constants.Padding.xs
                        ) {
                            HStack(alignment: .bottom) {
                                AudioLevelIcon(isActive: viewModel.activeOrCurrentSet?.state == .started)
                                
                                Text(viewModel.exercise.name)
                                    .font(Fonts.headline)
                                    .foregroundStyle(Color.primaryText)
                            }
                            
                            Text(setDurationString)
                                .font(Fonts.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Color.secondaryText)
                        }
                        
                        Spacer()
                        
                        HStack {
                            Text(heartRate)
                                .font(Fonts.subheadline)
                                .foregroundStyle(Color.secondaryText)
                            
                            Image(systemName: "heart.fill")
                                .font(Fonts.subheadline)
                                .foregroundStyle(Color.secondaryText)
                        }
                    }
                    .frame(height: bottomBarHeight)
                    .padding(.horizontal, Constants.Padding.l)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.max))
                    
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        if let onActionTap {
                            onActionTap()
                        } else {
                            viewModel.cycleCurrentSetState()
                        }
                    } label: {
                        Image(systemName: stateSymbol)
                            .font(Fonts.title)
                            .foregroundStyle(Color.primaryText)
                    }
                    .frame(width: bottomBarHeight, height: bottomBarHeight)
                }
                .glassEffect()
            }
        }
    }
}

struct AudioLevelIcon: View {
    var levels: [Int]
    var tintColor: Color
    
    init(isActive: Bool) {
        self.levels = isActive ? [3, 1, 2, 4] : [1, 1, 1, 1]
        self.tintColor = isActive ? Color.orange : Color.blue
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<levels.count, id: \.self) { columnIndex in
                VStack(spacing: 1) {
                    ForEach(0..<levels[columnIndex], id: \.self) { _ in
                        Capsule()
                            .fill(tintColor)
                            .frame(width: 5, height: 3)
                    }
                }
            }
        }
    }
}

#Preview {
    ActiveWorkoutView()
}
