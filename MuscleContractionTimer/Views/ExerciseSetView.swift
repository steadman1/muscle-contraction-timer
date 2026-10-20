//
//  ExerciseSetView.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/19/26.
//

import SwiftUI
import Combine

let setRowHeight: CGFloat = 40 // used in SetRowBoxes.swift
fileprivate let deleteActionWidth: CGFloat = setRowHeight
fileprivate let pageSpacing: CGFloat = 8
fileprivate let peekSliverWidth: CGFloat = setRowHeight

private enum SetRowSwipePage: Int {
    case inputs = 0
    case contractionTimings = 1
    case deleteAction = 2
}

struct ExerciseSetView: View {

    @ObservedObject var set: ExerciseSet
    
    let index: Int
    var onDelete: (() -> Void)?
    
    @State private var dragOffset: CGFloat = 0
    @State private var swipePage: SetRowSwipePage = .inputs
    @State private var pagerViewportWidth: CGFloat = 260
    
    init(_ index: Int, _ set: ExerciseSet, onDelete: (() -> Void)? = nil) {
        self.index = index
        self.set = set
        self.onDelete = onDelete
    }
    
    // Width of Page 1 (Timings) reduced by peekSliverWidth so a sliver of Page 0 remains visible on the left
    private var timingsPageWidth: CGFloat {
        max(1, pagerViewportWidth - peekSliverWidth - pageSpacing)
    }
    
    // Distance required to page from [Weight | Reps | Play] to [Eccentric | Concentric]
    private var pageStepDistance: CGFloat {
        max(1, pagerViewportWidth - peekSliverWidth)
    }
    
    // Total negative offset to reach the Delete reveal state
    private var maxNegativeOffset: CGFloat {
        onDelete != nil ? -(pageStepDistance + deleteActionWidth) : -pageStepDistance
    }
    
    // Translates the inner pager between Page 0 and Page 1
    private var innerPagerOffset: CGFloat {
        min(0, max(-pageStepDistance, dragOffset))
    }
    
    // Translates the entire row left only after Page 1 is reached, revealing the Delete button
    private var rowDeleteOffset: CGFloat {
        dragOffset < -pageStepDistance ? (dragOffset + pageStepDistance) : 0
    }
    
    private var deleteRevealProgress: CGFloat {
        min(max(-rowDeleteOffset / deleteActionWidth, 0), 1)
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if onDelete != nil {
                deleteSetContent
            }
            
            exerciseSetDetails
                .simultaneousGesture(
                    DragGesture(
                        minimumDistance: 10,
                        coordinateSpace: .local
                    )
                    .onChanged { handleDragChanged(value: $0) }
                    .onEnded { handleDragEnded(value: $0) }
                )
        }
        // swipe to timings immediately after timing processing finishes
        .onChange(of: set.isAnalyzingContraction) { _, isAnalyzing in
            if !isAnalyzing && set.state == .finished {
                snapToPage(.contractionTimings, animated: true)
            }
        }
        .onChange(of: set.state) { _, newState in
            if newState == .notStarted {
                snapToPage(.inputs, animated: true)
            }
        }
    }
    
    private var deleteSetContent: some View {
        Button(role: .destructive) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                dragOffset = 0
                swipePage = .inputs
            }
            onDelete?()
        } label: {
            Image(systemName: "minus.circle")
                .font(Fonts.headline)
                .foregroundStyle(Color.red)
        }
        .frame(width: deleteActionWidth)
        .opacity(deleteRevealProgress)
        .scaleEffect(0.5 + (0.5 * deleteRevealProgress), anchor: .trailing)
    }
    
    private var exerciseSetDetails: some View {
        HStack(spacing: pageSpacing) {
            Button {
                // ignoring the set type for simplicity
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
            
            // Sliding Viewport: Page 0 = [Weight | Reps | Play], Page 1 = [Sliver + Eccentric | Concentric]
            GeometryReader { geo in
                let width = geo.size.width
                HStack(spacing: pageSpacing) {
                    // Page 0: Weight, Reps, and Play/Finish Button (moves together on swipe)
                    HStack(spacing: pageSpacing) {
                        SetRowInputBox(set: set, text: $set.weight, unit: "lbs")
                        SetRowInputBox(set: set, text: $set.reps, unit: "reps")
                        cycleStateButton
                    }
                    .frame(width: width, height: setRowHeight)
                    
                    // Page 1: Eccentric & Concentric Contraction Timing Boxes
                    HStack(spacing: pageSpacing) {
                        SetRowTimingBox(
                            set: set,
                            duration: set.eccentricDuration,
                            isAnalyzing: set.isAnalyzingContraction,
                            unit: "ecc"
                        )
                        SetRowTimingBox(
                            set: set,
                            duration: set.concentricDuration,
                            isAnalyzing: set.isAnalyzingContraction,
                            unit: "con"
                        )
                    }
                    .frame(width: timingsPageWidth, height: setRowHeight)
                }
                .offset(x: innerPagerOffset)
                .onAppear {
                    if width > 0 { pagerViewportWidth = width }
                }
                .onChange(of: width) { _, newWidth in
                    guard newWidth > 0 else { return }
                    pagerViewportWidth = newWidth
                    snapToPage(swipePage, animated: false)
                }
            }
            .frame(height: setRowHeight)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .contentShape(Rectangle())
        .offset(x: rowDeleteOffset)
    }
    
    private var cycleStateButton: some View {
        Button {
            if swipePage != .inputs {
                snapToPage(.inputs, animated: true)
            } else {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
                
                set.cycleState()
                
                // If analysis completed synchronously (e.g. <20 frames), swipe immediately
                if set.state == .finished && !set.isAnalyzingContraction {
                    snapToPage(.contractionTimings, animated: true)
                }
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
    
    private func anchorOffset(for page: SetRowSwipePage) -> CGFloat {
        switch page {
        case .inputs:
            return 0
        case .contractionTimings:
            return -pageStepDistance
        case .deleteAction:
            return onDelete != nil ? -(pageStepDistance + deleteActionWidth) : -pageStepDistance
        }
    }
    
    private func snapToPage(_ page: SetRowSwipePage, animated: Bool) {
        let target = anchorOffset(for: page)
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                swipePage = page
                dragOffset = target
            }
        } else {
            swipePage = page
            dragOffset = target
        }
    }
    
    private func handleDragChanged(value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        
        let baseOffset = anchorOffset(for: swipePage)
        let proposed = baseOffset + value.translation.width
        
        if proposed > 0 {
            dragOffset = proposed * 0.15
        } else if proposed < maxNegativeOffset {
            let excess = proposed - maxNegativeOffset
            dragOffset = maxNegativeOffset + (excess * 0.25)
        } else {
            dragOffset = proposed
        }
    }
    
    private func handleDragEnded(value: DragGesture.Value) {
        let baseOffset = anchorOffset(for: swipePage)
        let predictedEnd = baseOffset + value.predictedEndTranslation.width
        let actualEnd = baseOffset + value.translation.width
        
        let nextPage: SetRowSwipePage
        switch swipePage {
        case .inputs:
            if predictedEnd < -(pageStepDistance * 0.35) || actualEnd < -(pageStepDistance * 0.5) {
                nextPage = .contractionTimings
            } else {
                nextPage = .inputs
            }
            
        case .contractionTimings:
            let deleteThreshold = -pageStepDistance - (deleteActionWidth * 0.45)
            let returnThreshold = -(pageStepDistance * 0.65)
            
            if onDelete != nil && (predictedEnd < deleteThreshold || actualEnd < deleteThreshold) {
                nextPage = .deleteAction
            } else if predictedEnd > returnThreshold || actualEnd > returnThreshold {
                nextPage = .inputs
            } else {
                nextPage = .contractionTimings
            }
            
        case .deleteAction:
            let closeDeleteThreshold = -pageStepDistance - (deleteActionWidth * 0.55)
            if predictedEnd > -(pageStepDistance * 0.5) {
                nextPage = .inputs
            } else if predictedEnd > closeDeleteThreshold || actualEnd > closeDeleteThreshold {
                nextPage = .contractionTimings
            } else {
                nextPage = .deleteAction
            }
        }
        
        snapToPage(nextPage, animated: true)
    }
}
