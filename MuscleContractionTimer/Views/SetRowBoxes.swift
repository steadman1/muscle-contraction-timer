//
//  SetRowTimingBox.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/20/26.
//

import SwiftUI
import Combine

struct SetRowTimingBox: View {
    @ObservedObject var set: ExerciseSet
    let duration: TimeInterval?
    let isAnalyzing: Bool
    let unit: String
    
    private var formattedDuration: String {
        if isAnalyzing {
            return "..."
        }
        guard let duration = duration, duration > 0 else {
            return "0.0s"
        }
        return String(format: "%.2fs", duration)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(formattedDuration)
                .font(Fonts.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(set.stateStyle.primaryText)
            
            Text(unit)
                .font(Fonts.headline)
                .lineLimit(1)
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
    }
}

struct SetRowInputBox: View {
    
    @ObservedObject var set: ExerciseSet
    @Binding var text: String
    let unit: String
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Text(text.isEmpty ? "0" : text)
                    .font(Fonts.headline)
                    .fixedSize()
                    .opacity(0)
                    .overlay {
                        TextField("0", text: $text)
                            .font(Fonts.headline)
                            .fixedSize()
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
                            .foregroundStyle(
                                isFocused
                                    ? Color.primaryFocused
                                    : set.stateStyle.primaryText
                            )
                    }
            }
            .frame(height: setRowHeight)
            
            Text(unit)
                .font(Fonts.headline)
                .foregroundStyle(
                    isFocused
                        ? Color.primaryFocused
                        : set.stateStyle.secondaryText
                )
        }
        .padding(.horizontal, 10)
        .frame(height: setRowHeight)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Constants.Radius.m)
                .fill(
                    isFocused
                        ? Color.secondaryFocused
                        : set.stateStyle.foreground
                )
                .strokeBorder(
                    isFocused
                        ? Color.primaryFocused.opacity(0.1)
                        : set.stateStyle.stroke,
                    lineWidth: Constants.strokeWidth
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            isFocused = true
        }
    }
}
