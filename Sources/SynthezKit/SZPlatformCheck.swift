//
//  SZPlatformCheck.swift
//  SynthezKit
//

import Foundation

#if !canImport(UIKit) && !canImport(AppKit)
    #error("SynthezKit needs UIKit or AppKit")
#endif

#if canImport(UIKit)
    import UIKit

    public typealias SZPlatformView = UIView
#elseif canImport(AppKit)
    import AppKit

    public typealias SZPlatformView = NSView
#endif
