//
//  ActiveWorkoutView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/22/26.
//

import SwiftUI
import Combine

fileprivate let bottomBarHeight: CGFloat = 64

struct ActiveWorkoutView: View {
    
    @StateObject private var exerciseViewModel = ExerciseViewModel(
        exercise: Exercise(
            name: "Back Squat",
            equipmentName: "Barbell",
            demonstrationImage: .init("squat")
        ),
        sets: [
            .init(weight: 135, reps: 8),
            .init(weight: 135, reps: 7),
            .init(weight: 135, reps: 6)
        ]
    )
    @ObservedObject private var tracker = SetMotionTracker.shared
    
    @State private var workoutStartDate: Date?
    @State private var now: Date = Date()
    
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    private var activeOrLastSet: ExerciseSet? {
        if let activeID = tracker.activeSetID,
           let active = exerciseViewModel.sets.first(where: { $0.id == activeID }) {
            return active
        }
        return exerciseViewModel.activeOrCurrentSet
    }
    
    private var setDurationString: String {
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
    
    private var workoutDurationString: String {
        guard let start = workoutStartDate else {
            return "00:00"
        }
        let elapsed = max(0, now.timeIntervalSince(start))
        return formatDuration(elapsed)
    }
    
    var body: some View {
        ScrollView {
            ExerciseView(viewModel: exerciseViewModel)
                .padding(Constants.Padding.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.background)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top) {
            HeaderView(timeString: workoutDurationString)
                .padding(.horizontal, Constants.Padding.m)
        }
        .safeAreaInset(edge: .bottom) {
            FooterView(
                viewModel: exerciseViewModel,
                setDurationString: setDurationString
            )
            .padding(.horizontal, Constants.Padding.m)
        }
        .onAppear {
            if workoutStartDate == nil {
                workoutStartDate = Date()
            }
            now = Date()
        }
        .onReceive(timer) { date in
            now = date
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
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
                            HStack {
                                AudioLevelIcon()
                                
                                Text(viewModel.exercise.name)
                                    .font(Fonts.subtitle)
                                    .foregroundStyle(Color.primaryText)
                            }
                            
                            Text(setDurationString)
                                .font(Fonts.headline)
                                .monospacedDigit()
                                .foregroundStyle(Color.primaryText)
                        }
                        
                        Spacer()
                        
                        HStack {
                            Text(heartRate)
                                .font(Fonts.headline)
                                .foregroundStyle(Color.secondaryText)
                            
                            Image(systemName: "heart.fill")
                                .font(Fonts.headline)
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
    var levels: [Int] = [3, 1, 2, 4]
    var tintColor: Color = .orange
    var segmentWidth: CGFloat = 5
    var segmentHeight: CGFloat = 3
    var verticalSpacing: CGFloat = 1
    var horizontalSpacing: CGFloat = 2

    var body: some View {
        HStack(alignment: .bottom, spacing: horizontalSpacing) {
            ForEach(0..<levels.count, id: \.self) { columnIndex in
                VStack(spacing: verticalSpacing) {
                    ForEach(0..<levels[columnIndex], id: \.self) { _ in
                        Capsule()
                            .fill(tintColor)
                            .frame(width: segmentWidth, height: segmentHeight)
                    }
                }
            }
        }
    }
}

#Preview {
    ActiveWorkoutView()
}

#Preview("FooterView") {
    FooterView(
        viewModel: ExerciseViewModel(
            exercise: Exercise(name: "Back Squat", equipmentName: "Barbell", demonstrationImage: .init("squat")),
            sets: [.init(weight: 135, reps: 8)]
        ),
        setDurationString: "00:15"
    )
    .padding()
    .background(Color.background)
}
