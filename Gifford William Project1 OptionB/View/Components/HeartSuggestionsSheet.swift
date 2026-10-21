import SwiftUI

struct HeartSuggestionsSheet: View {
    @ObservedObject var viewModel: OneFactViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingHeartSuggestions {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(AppTheme.accent)
                        Text("Finding broader topics…")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(AppTheme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.heartSuggestions.isEmpty {
                    ContentUnavailableView(
                        "No broad topics",
                        systemImage: "sparkles",
                        description: Text("This article didn’t suggest niches broad enough to match future facts.")
                    )
                } else {
                    List {
                        ForEach(viewModel.heartSuggestions) { interest in
                            Button {
                                viewModel.toggleHeartSuggestion(interest.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: viewModel.selectedHeartSuggestionIDs.contains(interest.id)
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .foregroundStyle(
                                            viewModel.selectedHeartSuggestionIDs.contains(interest.id)
                                            ? AppTheme.accent
                                            : AppTheme.muted
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(interest.label)
                                            .font(.system(.body, design: .rounded).weight(.semibold))
                                            .foregroundStyle(AppTheme.ink)
                                        Text(interest.source == .default ? "From your catalog" : "New topic")
                                            .font(.caption)
                                            .foregroundStyle(AppTheme.muted)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(AppTheme.paper.ignoresSafeArea())
            .navigationTitle("More like this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") {
                        viewModel.dismissHeartSheet()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !viewModel.isLoadingHeartSuggestions, !viewModel.heartSuggestions.isEmpty {
                    VStack(spacing: 10) {
                        Button {
                            viewModel.confirmHeartSuggestionsAddAndUse()
                        } label: {
                            Text("Add & use in Interests")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(.white)
                                .background(
                                    AppTheme.accent.opacity(
                                        viewModel.selectedHeartSuggestionIDs.isEmpty ? 0.45 : 1
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.selectedHeartSuggestionIDs.isEmpty)

                        Button {
                            viewModel.confirmHeartSuggestionsAddOnly()
                        } label: {
                            Text("Add to available interests")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(AppTheme.accent)
                                .background(AppTheme.accentSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.selectedHeartSuggestionIDs.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
