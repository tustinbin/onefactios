import SwiftUI

struct SavedView: View {
    @ObservedObject var viewModel: OneFactViewModel

    var body: some View {
        Group {
            if viewModel.showHistory {
                HistoryView(viewModel: viewModel)
            } else if let fact = viewModel.selectedSavedFact {
                SavedFactDetailView(fact: fact, viewModel: viewModel)
            } else {
                SavedFactListView(viewModel: viewModel)
            }
        }
        .background(AppTheme.paperGradient.ignoresSafeArea())
    }
}

// MARK: - List

private struct SavedFactListView: View {
    @ObservedObject var viewModel: OneFactViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    searchField
                    sortControls

                    if viewModel.saved.isEmpty {
                        Text("Save a fact from Learn to build this list.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                            .padding(.vertical, 24)
                    } else if viewModel.filteredSortedSaved.isEmpty {
                        Text("No saved facts match “\(viewModel.savedSearchText)”.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                            .padding(.vertical, 24)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.filteredSortedSaved) { fact in
                                Button {
                                    viewModel.openSavedFact(fact)
                                } label: {
                                    SavedTitleRow(fact: fact)
                                }
                                .buttonStyle(.plain)

                                if fact.id != viewModel.filteredSortedSaved.last?.id {
                                    Divider()
                                        .background(AppTheme.line)
                                }
                            }
                        }
                        .padding(.vertical, 4)
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
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Saved")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(viewModel.saved.isEmpty
                     ? "Facts you keep for later."
                     : "\(viewModel.saved.count) saved — tap a title to open the card.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                viewModel.openHistory()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.accentSoft)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Facts you’ve already seen")
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.muted)
            TextField("Search saved facts", text: $viewModel.savedSearchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .submitLabel(.search)
            if !viewModel.savedSearchText.isEmpty {
                Button {
                    viewModel.savedSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.accentSoft.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var sortControls: some View {
        HStack(spacing: 8) {
            Text("Sort")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

            ForEach(OneFactViewModel.SavedSortField.allCases) { field in
                Button {
                    viewModel.toggleSavedSortField(field)
                } label: {
                    Text(field.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(viewModel.savedSortField == field ? .white : AppTheme.inkSoft)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(viewModel.savedSortField == field ? AppTheme.accent : AppTheme.surface)
                        )
                        .overlay(
                            Capsule()
                                .stroke(AppTheme.line, lineWidth: viewModel.savedSortField == field ? 0 : 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            Button {
                viewModel.toggleSavedSortDirection()
            } label: {
                Label(
                    viewModel.savedSortAscending ? "Ascending" : "Descending",
                    systemImage: viewModel.savedSortAscending
                        ? "arrow.up"
                        : "arrow.down"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AppTheme.accentSoft)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SavedTitleRow: View {
    let fact: Fact

    private var dateLabel: String {
        guard let savedAt = fact.savedAt else { return "Saved" }
        return savedAt.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let imageURL = fact.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        AppTheme.accentSoft
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.accentSoft)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                    }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(fact.title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dateLabel)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Detail (single interactive card)

private struct SavedFactDetailView: View {
    let fact: Fact
    @ObservedObject var viewModel: OneFactViewModel

    private var isFlipped: Bool {
        viewModel.savedFlippedID == fact.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                backButton

                FactCard(
                    fact: fact,
                    isFlipped: isFlipped,
                    detail: viewModel.savedDetail(for: fact.id),
                    isLoadingDetail: viewModel.isSavedDetailLoading(fact.id),
                    detailFailed: viewModel.didSavedDetailFail(fact.id),
                    onFlip: { viewModel.toggleSavedCardFlip(fact) }
                )

                actionRow
                backButton
            }
            .padding(20)
            .padding(.bottom, 8)
            .appContentColumn()
        }
    }

    private var backButton: some View {
        Button {
            viewModel.closeSavedFact()
        } label: {
            Label("Back to saved", systemImage: "chevron.left")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.accentSoft)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            FactActionToolbar(
                fact: fact,
                viewModel: viewModel,
                isFlipped: isFlipped,
                compact: true
            )

            Button {
                viewModel.removeSaved(fact.id)
            } label: {
                Text("Remove from saved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.danger)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $viewModel.showHeartSheet) {
            HeartSuggestionsSheet(viewModel: viewModel)
        }
    }
}
