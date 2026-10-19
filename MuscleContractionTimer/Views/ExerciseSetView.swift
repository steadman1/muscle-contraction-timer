//
//  ExerciseSetView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/19/26.
//

import SwiftUI
import Combine

fileprivate let setRowHeight: CGFloat = 44

struct ExerciseSetView: View {

    @ObservedObject var set: ExerciseSet
    
    let index: Int
    
    init(_ index: Int, _ set: ExerciseSet) {
        self.index = index
        self.set = set
    }
    
    var body: some View {
        HStack {
            Button {
                // no set type picker bc this is just a prototype
            } label: {
                Text("\(index + 1)")
                    .foregroundStyle(set.stateStyle.primaryText)
                    .font(Fonts.headline)
                    .frame(width: setRowHeight, height: setRowHeight)
                    .foregroundStyle(set.stateStyle.cycleStateForeground)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.Radius.max)
                            .fill(set.stateStyle.foreground)
                            .strokeBorder(
                                set.stateStyle.stroke,
                                lineWidth: Constants.strokeWidth
                            )
                    )
            }
            
            SetRowInputBox(set: set, text: $set.weight, unit: "lbs")
            
            SetRowInputBox(set: set, text: $set.reps, unit: "reps")
            
            Button {
                set.cycleState()
            } label: {
                Image(systemName: set.stateSymbol)
                    .font(Fonts.headline)
                    .frame(width: setRowHeight, height: setRowHeight)
                    .foregroundStyle(set.stateStyle.cycleStateForeground)
                    .background(
                        RoundedRectangle(cornerRadius: Constants.Radius.max)
                            .fill(set.stateStyle.cycleStateBackground)
                            .strokeBorder(
                                set.stateStyle.stroke,
                                lineWidth: Constants.strokeWidth
                            )
                    )
            }
        }
    }
}

struct SetRowInputBox: View {
    
    @ObservedObject var set: ExerciseSet
    @Binding var text: String
    let unit: String
    
    // not handling the text field color change to blue when focused
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                // textbox shrinks width of the input area
                Text(text.isEmpty ? "0" : text)
                    .font(Fonts.headline)
                    .opacity(0)
                    .overlay {
                        TextField("0", text: $text)
                            .font(Fonts.headline)
                            .keyboardType(.numberPad)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                            .focused($isFocused)
                            .onReceive(Just(text)) { newValue in
                                let filtered = newValue.filter { "0123456789".contains($0) }
                                if filtered != newValue {
                                    text = filtered
                                }
                            }
                            .foregroundStyle(set.stateStyle.primaryText)
                    }
            }
            .frame(height: setRowHeight)
            
            Text(unit)
                .font(Fonts.headline)
                .foregroundStyle(set.stateStyle.secondaryText)
        }
        .padding(.horizontal, 10)
        .frame(height: setRowHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.m)
                .fill(set.stateStyle.foreground)
                .strokeBorder(
                    set.stateStyle.stroke,
                    lineWidth: Constants.strokeWidth
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
    }
}
