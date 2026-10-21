import SwiftUI

struct LandingView: View {
    @ObservedObject var viewModel: OneFactViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool {
        AppLayout.isLandscapePhone(verticalSizeClass: verticalSizeClass)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isLandscape ? 18 : 28) {
                Text("One Fact")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.muted)

                VStack(alignment: .leading, spacing: isLandscape ? 8 : 12) {
                    Text("Edify yourself, one fact at a time.")
                        .font(.system(size: isLandscape ? 28 : 34, weight: .semibold, design: .serif))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("A quiet place for one deliberate fact — not a feed, not the news.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Group {
                    if isLandscape {
                        HStack(spacing: 12) {
                            PrimaryButton(title: "One Fact") {
                                viewModel.openLearn(loadIfNeeded: true)
                            }
                            Button {
                                viewModel.openChallenge()
                            } label: {
                                Text("Challenge")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundStyle(AppTheme.accent)
                                    .background(AppTheme.accentSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        VStack(spacing: 12) {
                            PrimaryButton(title: "One Fact") {
                                viewModel.openLearn(loadIfNeeded: true)
                            }

                            Button {
                                viewModel.openChallenge()
                            } label: {
                                Text("Challenge")
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .foregroundStyle(AppTheme.accent)
                                    .background(AppTheme.accentSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                howItWorks

                homeStatsFooter
            }
            .padding(.vertical, isLandscape ? 16 : 24)
            .padding(.bottom, 12)
            .padding(.horizontal, AppLayout.horizontalPadding(verticalSizeClass: verticalSizeClass))
            .appContentColumn()
        }
        .background(AppTheme.paperGradient.ignoresSafeArea())
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How this place works")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)

            HomeGuideRow(
                symbol: "square.grid.2x2.fill",
                title: "Interests shape the stream",
                detail: "Pick niches you care about. On One Fact, switch to Interests — new facts lean toward those topics instead of pure random."
            )

            HomeGuideRow(
                symbol: "bookmark.fill",
                title: "Save what you want to keep",
                detail: "Tap the bookmark on a fact. It lands in Library → Saved. History keeps everything you’ve already seen."
            )

            HomeGuideRow(
                symbol: "sparkles",
                title: "Find related niches",
                detail: "Tap the stars on a fact to pull broader topics from the article. Add them to Interests (or use them right away) so future facts lean that way."
            )

            HomeGuideRow(
                symbol: "flame.fill",
                title: "Challenge is optional practice",
                detail: "Five facts, then a quick recall — titles, excerpts, and sometimes an image match. Random or your Interests."
            )

            Button {
                viewModel.openInterests()
            } label: {
                Text("Choose interests")
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        )
    }

    private var homeStatsFooter: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(AppTheme.line.opacity(0.8))
                .frame(height: 1)

            HStack(spacing: 0) {
                HomeStatCell(value: "\(viewModel.seenIDs.count)", label: "Facts Seen")
                HomeStatCell(value: "\(viewModel.saved.count)", label: "Facts Saved")
                HomeStatCell(value: "\(viewModel.challengesCompleted)", label: "Quizzes Taken")
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.homeStatsLabel)
    }
}

private struct HomeStatCell: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct HomeGuideRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
