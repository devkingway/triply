import SwiftUI
import Lottie

/// Looping paper-plane illustration for empty screens (plane_loop.json).
struct PlaneAnimation: View {
    var size: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LottieView(animation: .named("plane_loop"))
            .playbackMode(reduceMotion
                          ? .paused(at: .progress(0.25))
                          : .playing(.fromProgress(0, toProgress: 1, loopMode: .loop)))
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// One-shot "saved" check mark (success_check.json). Calls `onFinish` when done.
struct SuccessAnimation: View {
    var size: CGFloat = 130
    var onFinish: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LottieView(animation: .named("success_check"))
            .playbackMode(reduceMotion
                          ? .paused(at: .progress(1))
                          : .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce)))
            .animationDidFinish { _ in onFinish() }
            .resizable()
            .frame(width: size, height: size)
            .accessibilityLabel("Saved")
            .task {
                // Reduce Motion shows the final frame, so finish shortly after.
                if reduceMotion {
                    try? await Task.sleep(for: .milliseconds(700))
                    onFinish()
                }
            }
    }
}
