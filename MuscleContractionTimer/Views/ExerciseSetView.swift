//
//  ExerciseSetView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/19/26.
//

import SwiftUI
import Combine

fileprivate let setRowHeight: CGFloat = 40
fileprivate let deleteActionWidth: CGFloat = setRowHeight

struct ExerciseSetView: View {

    @ObservedObject var set: ExerciseSet
    
    let index: Int
    var onDelete: (() -> Void)?
    
    @State private var offset: CGFloat = 0
    @State private var isSwipedOpen: Bool = false
    
    init(_ index: Int, _ set: ExerciseSet, onDelete: (() -> Void)? = nil) {
        self.index = index
        self.set = set
        self.onDelete = onDelete
    }
    
    private var revealProgress: CGFloat {
        min(max(-offset / deleteActionWidth, 0), 1)
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if onDelete != nil {
                deleteSetContent
            }
            
            exerciseSetDetails
                .simultaneousGesture(
                    DragGesture(
                        minimumDistance: 0,
                        coordinateSpace: .local
                    )
                    .onChanged { revealDeleteSetContent(value: $0) }
                    .onEnded { finishRevealDeleteSetContent(value: $0) }
                )
        }
    }
    
    private var deleteSetContent: some View {
        Button(role: .destructive) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                offset = 0
                isSwipedOpen = false
            }
            onDelete?()
        } label: {
            Image(systemName: "minus.circle")
                .font(Fonts.headline)
                .foregroundStyle(Color.red)
        }
        .frame(width: deleteActionWidth)
        .opacity(revealProgress)
        .scaleEffect(0.5 + (0.5 * revealProgress), anchor: .trailing)
    }
    
    private var exerciseSetDetails: some View {
        HStack {
            Button {
                // no set type picker bc this is just a prototype
            } label: {
                Text("\(index + 1)")
                    .font(Fonts.headline)
                    .frame(width: setRowHeight, height: setRowHeight)
                    .foregroundStyle(set.stateStyle.primaryText)
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
                if isSwipedOpen {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        offset = 0
                        isSwipedOpen = false
                    }
                } else {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    
                    set.cycleState()
                }
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
        .contentShape(Rectangle())
        .offset(x: offset)
    }
    
    func revealDeleteSetContent(value: DragGesture.Value) {
        guard onDelete != nil else { return }
        // Ignore vertical scrolls
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        
        let baseOffset: CGFloat = isSwipedOpen ? -deleteActionWidth : 0
        let proposed = baseOffset + value.translation.width
        
        if proposed < 0 {
            if proposed < -deleteActionWidth {
                let excess = proposed + deleteActionWidth
                offset = -deleteActionWidth + (excess * 0.25)
            } else {
                offset = proposed
            }
        } else {
            offset = proposed * 0.15
        }
    }
    
    func finishRevealDeleteSetContent(value: DragGesture.Value) {
        guard onDelete != nil else { return }
        let baseOffset: CGFloat = isSwipedOpen ? -deleteActionWidth : 0
        let predictedEnd = baseOffset + value.predictedEndTranslation.width
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if predictedEnd < -(deleteActionWidth * 0.5) {
                offset = -deleteActionWidth
                isSwipedOpen = true
            } else {
                offset = 0
                isSwipedOpen = false
            }
        }
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
                // textbox shrinks width of the input area
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
                                // not very elegant, ik
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
