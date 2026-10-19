//
//  ExerciseView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/14/26.
//

import SwiftUI

struct ExerciseView: View {
    @StateObject var viewModel: ExerciseViewModel
    
    var body: some View {
        VStack(spacing: Constants.Padding.m) {
            VStack(spacing: Constants.Padding.l) {
                HStack {
                    exerciseInfoTitle
                    
                    Spacer()
                    
                    exerciseInfoTitleButton(systemName: "stopwatch")
                    exerciseInfoTitleButton(systemName: "ellipsis")
                }
                
                VStack {
                    ForEach(viewModel.sets.enumerated(), id: \.0) { index, set in
                        
                        ExerciseSetView(index, set)
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
            .compositingGroup()
            .shadow(color: Color.shadow, radius: 12)
            .shadow(color: Color.shadow, radius: 4)
            
            HStack {
                
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Progression")
                }
                .font(Fonts.headline)
                .foregroundStyle(Color.secondaryText)
                .frame(maxWidth: .infinity)
                
                
                RoundedRectangle(cornerRadius: Constants.Radius.max)
                    .frame(width: Constants.strokeWidth, height: 24)
                    .foregroundStyle(Color.tertiaryText)
                
                
                Button {
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
    
    // return styled button from sf symbol name
    func exerciseInfoTitleButton(systemName: String) -> some View {
        Group {
            Image(systemName: systemName)
                .font(Fonts.headline)
                .foregroundStyle(Color.secondaryText)
                
        }
        .frame(width: 40, height: 40)
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
