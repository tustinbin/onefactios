import SwiftUI

struct LearnView: View {
    @ObservedObject var viewModel: OneFactViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: 200)
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

                HStack(spacing: 12) {
                    LiquidIconButton(
                        systemName: viewModel.currentFact.map { viewModel.isSaved($0.id) } == true
                            ? "bookmark.fill" : "bookmark",
                        isActive: viewModel.currentFact.map { viewModel.isSaved($0.id) } == true,
                        isEnabled: viewModel.currentFact != nil
                    ) {
                        viewModel.toggleSaveCurrent()
                    }

                    // Sparkles = “more like this” / add related topics (not a favorite heart).
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
                            Text("Read more")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 14)
                                .frame(height: 44)
                        }
                        .modifier(ReadMoreChrome())
                    }

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $viewModel.showHeartSheet) {
            HeartSuggestionsSheet(viewModel: viewModel)
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
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
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
