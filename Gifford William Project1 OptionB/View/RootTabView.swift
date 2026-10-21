import SwiftUI

struct RootTabView: View {
    @ObservedObject var viewModel: OneFactViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        AppLayout.isLandscapePhone(verticalSizeClass: verticalSizeClass)
    }

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
                case .challenge:
                    DailyChallengeView(viewModel: viewModel)
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
                    .padding(.bottom, isLandscape ? 52 : 96)
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

    /// Home (left) · Saved · One Fact (center) · Challenge · Interests
    private var bottomNav: some View {
        HStack(spacing: 0) {
            navButton("Home", systemImage: "house.fill", screen: .landing) {
                viewModel.openHome()
            }
            navButton("Library", systemImage: "bookmark.fill", screen: .saved) {
                viewModel.openSaved()
            }
            navButton("One Fact", systemImage: "lightbulb.fill", screen: .learn) {
                viewModel.openLearn(loadIfNeeded: true)
            }
            navButton("Challenge", systemImage: "flame.fill", screen: .challenge) {
                viewModel.openChallenge()
            }
            navButton("Interests", systemImage: "square.grid.2x2.fill", screen: .interests) {
                viewModel.openInterests()
            }
        }
        .padding(.top, isLandscape ? 4 : 10)
        .padding(.bottom, isLandscape ? 2 : 6)
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
            Group {
                if isLandscape {
                    // Landscape: icon + label side-by-side to save vertical space.
                    HStack(spacing: 5) {
                        Image(systemName: systemImage)
                            .font(.footnote.weight(.semibold))
                        Text(title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.vertical, 6)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: systemImage)
                            .font(.body.weight(.semibold))
                        Text(title)
                            .font(.caption2.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                }
            }
            .foregroundStyle(viewModel.screen == screen ? AppTheme.accent : AppTheme.muted)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
