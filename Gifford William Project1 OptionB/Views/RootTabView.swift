import SwiftUI

struct RootTabView: View {
    @ObservedObject var viewModel: OneFactViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.paper
                .ignoresSafeArea()

            Group {
                switch viewModel.screen {
                case .landing:
                    LandingView(viewModel: viewModel)
                case .learn:
                    LearnView(viewModel: viewModel)
                case .saved:
                    SavedView(viewModel: viewModel)
                case .interests:
                    InterestsView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let toast = viewModel.toastMessage {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppTheme.ink.opacity(0.92))
                    .clipShape(Capsule())
                    .padding(.bottom, 96)
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomNav
        }
        .onAppear {
            viewModel.restoreIfNeeded()
        }
    }

    /// Home · Saved · Learn · Interests
    private var bottomNav: some View {
        HStack(spacing: 0) {
            navButton("Home", systemImage: "house.fill", screen: .landing) {
                viewModel.openHome()
            }
            navButton("Saved", systemImage: "bookmark.fill", screen: .saved) {
                viewModel.openSaved()
            }
            navButton("Learn", systemImage: "lightbulb.fill", screen: .learn) {
                viewModel.openLearn(loadIfNeeded: true)
            }
            navButton("Interests", systemImage: "square.grid.2x2.fill", screen: .interests) {
                viewModel.openInterests()
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background {
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                Rectangle().fill(.clear).glassEffect(.regular, in: .rect)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.line.opacity(0.6))
                .frame(height: 0.5)
        }
    }

    private func navButton(
        _ title: String,
        systemImage: String,
        screen: OneFactViewModel.Screen,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(viewModel.screen == screen ? AppTheme.accent : AppTheme.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
