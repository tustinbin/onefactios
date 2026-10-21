import SwiftUI

/// Facts you’ve seen in One Fact or Challenge — opened from the Library tab.
struct HistoryView: View {
    @ObservedObject var viewModel: OneFactViewModel

    var body: some View {
        Group {
            if let fact = viewModel.selectedHistoryFact {
                historyDetail(fact)
            } else {
                historyList
            }
        }
    }

    private var historyList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("History")
                            .font(.system(.title2, design: .serif).weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Everything you’ve seen — tap a title to open the card again.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(AppTheme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        viewModel.closeHistory()
                    } label: {
                        Text("Saved")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentSoft)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.factHistory.isEmpty {
                    Text("No history yet — open One Fact or run a Challenge.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.factHistory) { fact in
                            Button {
                                viewModel.openHistoryFact(fact)
                            } label: {
                                Text(fact.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.ink)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if fact.id != viewModel.factHistory.last?.id {
                                Divider().background(AppTheme.line)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.line, lineWidth: 1)
                    )
                }
            }
            .padding(20)
            .padding(.bottom, 8)
            .appContentColumn()
        }
    }

    private func historyDetail(_ fact: Fact) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    viewModel.closeHistoryFact()
                } label: {
                    Label("Back to history", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)

                FactCard(
                    fact: fact,
                    isFlipped: viewModel.historyFlipped,
                    detail: viewModel.savedDetail(for: fact.id),
                    isLoadingDetail: viewModel.isSavedDetailLoading(fact.id),
                    detailFailed: viewModel.didSavedDetailFail(fact.id),
                    onFlip: { viewModel.toggleHistoryCardFlip() }
                )

                FactActionToolbar(
                    fact: fact,
                    viewModel: viewModel,
                    isFlipped: viewModel.historyFlipped,
                    compact: true
                )
            }
            .padding(20)
            .appContentColumn()
        }
        .sheet(isPresented: $viewModel.showHeartSheet) {
            HeartSuggestionsSheet(viewModel: viewModel)
        }
    }
}
