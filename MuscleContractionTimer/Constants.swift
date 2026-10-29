//
//  Constants.swift
//  MuscleContractionTimer
//
//  Created by Spencer Steadman on 10/15/26.
//

import SwiftUI

public enum Constants {
    public static let strokeWidth: CGFloat = 1
    public static let cardShadow: ShadowStyle = .drop(color: Color.shadow, radius: 5)
    
    public enum Radius {
        public static let max: CGFloat = 2048
        
        public static let xl: CGFloat = 32
        public static let l: CGFloat = 24
        public static let m: CGFloat = 16
        public static let s: CGFloat = 12
        public static let xs: CGFloat = 8
        public static let xxs: CGFloat = 4
    }
    
    public enum Padding {
        public static let xl: CGFloat = 32
        public static let l: CGFloat = 24
        public static let m: CGFloat = 16
        public static let s: CGFloat = 8
        public static let xs: CGFloat = 4
    }
}

public enum Fonts {
    public static let title: Font = .system(size: 28, weight: .semibold, design: .rounded)
    public static let headline: Font = .system(size: 17, weight: .semibold, design: .rounded)
    public static let body: Font = .system(size: 17, weight: .medium, design: .rounded)
    public static let subheadline: Font = .system(size: 15, weight: .semibold, design: .rounded)
    public static let subhead: Font = .system(size: 15, weight: .medium, design: .rounded)
    public static let detail: Font = .system(size: 11, weight: .bold, design: .rounded)
}
