import SwiftUI

struct LandingView: View {
    @ObservedObject var viewModel: OneFactViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("One Fact")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.muted)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Edify yourself, one fact at a time.")
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(AppTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("One deliberate fact from history and culture—not a feed, not the news.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HomeStatsBanner(
                    title: "Your library",
                    subtitle: viewModel.homeStatsLabel
                )

                PrimaryButton(title: "Learn something new") {
                    viewModel.openLearn(loadIfNeeded: true)
                }

                Button {
                    viewModel.openInterests()
                } label: {
                    Text("Browse interests")
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .foregroundStyle(AppTheme.accent)
                }

                // Placeholder for Project 1 extras (progress, quizzes, etc.) — wired later.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Coming soon on Home")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("Project 1 extras — progress, checklists, and more — will live here.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.accentSoft.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(24)
            .padding(.bottom, 12)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.paperGradient.ignoresSafeArea())
    }
}

struct HomeStatsBanner: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
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
}
