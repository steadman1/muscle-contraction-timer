//
//  WorkoutTemplateView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/23/26.
//

import SwiftUI

fileprivate let cardSize: CGSize = .init(width: 188, height: 144)

struct WorkoutTemplateView: View {
    
    @StateObject var workoutViewModel: WorkoutViewModel
    @State private var isWorkoutPresented = false
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(Fonts.headline)
                    .foregroundStyle(Color.orange)
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .font(Fonts.headline)
                        .foregroundStyle(Color.primaryText)
                        .frame(width: 0, height: 0) // restrict size so that the non-square image wont cause weird ghost sizing after the clipShape is applied
                        .padding(Constants.Padding.m)
                }
                .background(Color.background)
                .clipShape(Circle())
            }
            
            Spacer()
            
            Text("Traditional Strength Training")
                .font(Fonts.subheadline)
                .foregroundStyle(Color.orange)
                .lineLimit(1)
            
            Text(workoutViewModel.name)
                .font(Fonts.headline)
                .foregroundStyle(Color.primaryText)
                .lineLimit(1)
            
            Text(workoutViewModel.exerciseCountDetails)
                .font(Fonts.subheadline)
                .foregroundStyle(Color.tertiaryText)
                .lineLimit(1)
            
        }
        .padding(Constants.Padding.m)
        .frame(width: cardSize.width, height: cardSize.height)
        .background(Color.foreground)
        .overlay {
            Circle()
                .fill(Color.orange.opacity(0.3))
                .frame(width: 96, height: 96)
                .blur(radius: 70)
        }
        .clipShape(RoundedRectangle(cornerRadius: Constants.Radius.l))
        .compositingGroup()
        .shadow(color: Color.shadow, radius: 4, y: 4)
        .onTapGesture {
            isWorkoutPresented.toggle()
        }
        .sheet(isPresented: $isWorkoutPresented) {
            ActiveWorkoutView(workoutViewModel: workoutViewModel)
        }
    }
}

#Preview {
    let viewModel = WorkoutViewModel(
        name: "Legs and Back",
        exercises: [
            ExerciseViewModel(
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
            ),
            ExerciseViewModel(
                exercise: Exercise(
                    name: "Pull Ups",
                    equipmentName: "Pull Up Bar",
                    demonstrationImage: .init("pull_up")
                ),
                sets: [
                    .init(weight: 45, reps: 6),
                    .init(weight: 45, reps: 5),
                    .init(weight: 45, reps: 4)
                ]
            )
        ]
    )
    
    VStack {
        WorkoutTemplateView(workoutViewModel: viewModel)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.background)
}
