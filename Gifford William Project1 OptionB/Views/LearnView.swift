import SwiftUI

struct LearnView: View {
    @ObservedObject var viewModel: OneFactViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        AppLayout.isLandscapePhone(verticalSizeClass: verticalSizeClass)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isLandscape ? 12 : 18) {
                header
                content
            }
            .padding(.horizontal, AppLayout.horizontalPadding(verticalSizeClass: verticalSizeClass))
            .padding(.top, isLandscape ? 12 : 20)
            .padding(.bottom, 8)
            .appContentColumn()
        }
        .background(AppTheme.paperGradient.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            stickyActions
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(viewModel.topicLabel())
                .font(.caption.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(isLandscape ? 1 : 2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)
            modeToggle
        }
    }

    private var modeToggle: some View {
        Picker("Fact mode", selection: Binding(
            get: { viewModel.mode },
            set: { viewModel.setMode($0) }
        )) {
            ForEach(FactMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: isLandscape ? 220 : 200)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            loadingCard
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                Text("Couldn’t load a fact right now")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(message)
                    .font(.body)
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.effectiveMode == .interests {
                    PrimaryButton(title: "Choose interests") {
                        viewModel.openInterests()
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .loaded:
            if let fact = viewModel.currentFact {
                FactCard(
                    fact: fact,
                    isFlipped: viewModel.isCardFlipped,
                    detail: viewModel.factDetail,
                    isLoadingDetail: viewModel.isLoadingDetail,
                    detailFailed: viewModel.detailFailed,
                    onFlip: { viewModel.toggleCardFlip() }
                )
            }
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
                .tint(AppTheme.accent)
            Text("Finding something worth knowing…")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("One deliberate fact—not a feed, not the news.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Always pinned — scroll the fact above it.
    private var stickyActions: some View {
        LiquidGlassBar {
            Group {
                if isLandscape {
                    HStack(spacing: 12) {
                        Button {
                            Task { await viewModel.loadNextFact() }
                        } label: {
                            Text(viewModel.loadState == .loading ? "Loading…" : "Next fact")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .frame(maxWidth: 200)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(AppTheme.accent.opacity(viewModel.loadState == .loading ? 0.55 : 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.loadState == .loading)

                        learnActionIcons
                    }
                } else {
                    VStack(spacing: 10) {
                        Button {
                            Task { await viewModel.loadNextFact() }
                        } label: {
                            Text(viewModel.loadState == .loading ? "Loading…" : "Next fact")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(AppTheme.accent.opacity(viewModel.loadState == .loading ? 0.55 : 1))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.loadState == .loading)

                        learnActionIcons
                    }
                }
            }
            .appContentColumn()
        }
        .sheet(isPresented: $viewModel.showHeartSheet) {
            HeartSuggestionsSheet(viewModel: viewModel)
        }
    }

    private var learnActionIcons: some View {
        HStack(spacing: 12) {
            LiquidIconButton(
                systemName: viewModel.currentFact.map { viewModel.isSaved($0.id) } == true
                    ? "bookmark.fill" : "bookmark",
                isActive: viewModel.currentFact.map { viewModel.isSaved($0.id) } == true,
                isEnabled: viewModel.currentFact != nil
            ) {
                viewModel.toggleSaveCurrent()
            }

            LiquidIconButton(
                systemName: "sparkles",
                isActive: viewModel.currentFact.map { viewModel.isHearted($0.id) } == true,
                isEnabled: viewModel.currentFact != nil
            ) {
                Task { await viewModel.heartCurrent() }
            }

            if let fact = viewModel.currentFact {
                FactShareLink(fact: fact)
                    .modifier(ShareChrome())
            } else {
                LiquidIconButton(systemName: "square.and.arrow.up", isEnabled: false) {}
            }

            if let url = viewModel.currentFact?.pageURL {
                Link(destination: url) {
                    Label(
                        viewModel.isCardFlipped ? "Read full article" : "Read more",
                        systemImage: "arrow.up.right"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.isCardFlipped ? .white : AppTheme.accent)
                    .padding(.horizontal, viewModel.isCardFlipped ? 16 : 14)
                    .frame(height: isLandscape ? 40 : 44)
                }
                .modifier(ReadMoreChrome(emphasized: viewModel.isCardFlipped))
                .animation(.easeInOut(duration: 0.25), value: viewModel.isCardFlipped)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ShareChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay { Circle().stroke(AppTheme.line.opacity(0.8), lineWidth: 0.5) }
                )
        }
    }
}

private struct ReadMoreChrome: ViewModifier {
    var emphasized: Bool = false

    func body(content: Content) -> some View {
        if emphasized {
            content
                .background(Capsule().fill(AppTheme.accent))
                .shadow(color: AppTheme.accent.opacity(0.35), radius: 8, y: 2)
        } else if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            content
                .glassEffect(.regular.tint(AppTheme.accentSoft), in: .capsule)
        } else {
            content
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay { Capsule().stroke(AppTheme.line.opacity(0.8), lineWidth: 0.5) }
                )
        }
    }
}
