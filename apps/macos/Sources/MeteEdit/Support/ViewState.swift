import SwiftUI

/// The macOS 26+ SDK declares `@State` as a macro whose implementation plugin ships only with Xcode.
/// This alias names the `State` property wrapper struct directly, so the app also builds with the
/// Command Line Tools alone. Behaviour is identical to `@State`.
typealias ViewState<Value> = SwiftUI.State<Value>
