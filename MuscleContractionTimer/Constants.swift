//
//  Constants.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/15/26.
//

import SwiftUI

class Constants {
//    enum ButtonSize: Double {
//        case
//    }
    
    static let strokeWidth: CGFloat = 1
    static let cardShadow: ShadowStyle = .drop(color: Color.shadow, radius: 5)
    
    class Radius {
        static let max: CGFloat = 2048
        
        static let xl: CGFloat = 32
        static let l: CGFloat = 24
        static let m: CGFloat = 16
        static let s: CGFloat = 12
        static let xs: CGFloat = 8
        static let xxs: CGFloat = 4
    }
    
    class Padding {
        static let xl: CGFloat = 32
        static let l: CGFloat = 24
        static let m: CGFloat = 16
        static let s: CGFloat = 8
        static let xs: CGFloat = 4
    }
}

class Fonts {
    static let title: Font = .system(size: 24, weight: .medium, design: .rounded)
    
    static let headline: Font = .system(size: 20, weight: .semibold, design: .rounded)
    
    static let body: Font = .system(size: 16, weight: .medium, design: .rounded)
    
    static let subheadline: Font = .system(size: 16, weight: .semibold, design: .rounded)
    static let subhead: Font = .system(size: 16, weight: .medium, design: .rounded)
}
