import SwiftUI

struct InterestsView: View {
    @ObservedObject var viewModel: OneFactViewModel
    @State private var customNicheDraft = ""
    @FocusState private var isCustomFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                createCustomNicheCard

                if !viewModel.selectedInterests.isEmpty {
                    sectionTitle("Categories in use")
                    chipGrid(for: viewModel.selectedInterests)
                }

                additionSection(
                    title: "Custom Additions",
                    emptyText: viewModel.additions.contains(where: { $0.source == .custom })
                        ? "All your typed niches are in use above. Deselect one to park it here."
                        : "Create a niche above — typed topics land here when not in use.",
                    interests: viewModel.availableHandwrittenAdditions
                )

                additionSection(
                    title: "Generated Additions",
                    emptyText: viewModel.additions.contains(where: { $0.source == .addition })
                        ? "All sparkle topics are in use above. Deselect one to park it here."
                        : "Tap sparkles on Learn for “more like this” topics. They land here when not in use.",
                    interests: viewModel.availableGeneratedAdditions
                )

                sectionTitle("Browse niches")
                ForEach(InterestCatalog.groups) { group in
                    NicheGroupCard(group: group, viewModel: viewModel)
                }
            }
            .padding(20)
            .padding(.bottom, 8)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.paperGradient.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            LiquidGlassBar {
                PrimaryButton(title: "Learn something new") {
                    viewModel.openLearn(loadIfNeeded: true)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your interests")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                if !viewModel.selectedIDs.isEmpty {
                    Button("Clear all") {
                        viewModel.clearAllNiches()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                }
            }
            Text("Put niches in use above. Typed topics park under Custom Additions; sparkle topics under Generated Additions. Delete only from those lists.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func additionSection(title: String, emptyText: String, interests: [Interest]) -> some View {
        sectionTitle(title)
        if interests.isEmpty {
            Text(emptyText)
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(interests) { interest in
                    HStack(spacing: 6) {
                        Button {
                            viewModel.toggleNiche(interest.id)
                        } label: {
                            NicheChip(
                                label: interest.label,
                                symbolName: interest.symbolName,
                                selected: false
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            viewModel.removeAddition(interest.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.muted)
                                .accessibilityLabel("Delete forever")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var createCustomNicheCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create your own")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Type a topic like “LEGO” or “Victorian railways.” Distinctive names match best.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                TextField("Niche name", text: $customNicheDraft)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.accentSoft.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .focused($isCustomFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(submitCustomNiche)

                Button("Add") {
                    submitCustomNiche()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(customNicheDraft.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                .opacity(customNicheDraft.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 ? 0.5 : 1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        )
    }

    private func submitCustomNiche() {
        let draft = customNicheDraft
        if viewModel.createCustomNiche(from: draft) {
            customNicheDraft = ""
            isCustomFieldFocused = false
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
    }

    private func chipGrid(for interests: [Interest]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
            ForEach(interests) { interest in
                Button {
                    viewModel.toggleNiche(interest.id)
                } label: {
                    NicheChip(
                        label: interest.label,
                        symbolName: interest.symbolName,
                        selected: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct NicheGroupCard: View {
    let group: InterestGroup
    @ObservedObject var viewModel: OneFactViewModel

    private var isExpanded: Bool {
        viewModel.expandedParentIDs.contains(group.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                viewModel.toggleParentExpanded(group.id)
            } label: {
                HStack {
                    Image(systemName: group.symbolName)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28)
                    Text(group.label)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack {
                    Button("Select all") {
                        viewModel.setGroupSelection(parentID: group.id, selectAll: true)
                    }
                    .font(.caption.weight(.semibold))
                    Button("Clear") {
                        viewModel.setGroupSelection(parentID: group.id, selectAll: false)
                    }
                    .font(.caption.weight(.semibold))
                }
                .foregroundStyle(AppTheme.accent)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(group.children) { interest in
                        Button {
                            viewModel.toggleNiche(interest.id)
                        } label: {
                            NicheChip(
                                label: interest.label,
                                symbolName: interest.symbolName,
                                selected: viewModel.selectedIDs.contains(interest.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        )
    }
}

private struct NicheChip: View {
    let label: String
    let symbolName: String
    var selected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.caption)
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(selected ? .white : AppTheme.inkSoft)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(selected ? AppTheme.accent : AppTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
