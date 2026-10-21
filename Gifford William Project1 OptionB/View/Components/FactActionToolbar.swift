import SwiftUI

/// Bookmark / sparkles / share / optional Read more — shared across Learn, Challenge, Saved, History.
struct FactActionToolbar: View {
    let fact: Fact
    @ObservedObject var viewModel: OneFactViewModel
    var isFlipped: Bool = false
    var showReadMore: Bool = true
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            LiquidIconButton(
                systemName: viewModel.isSaved(fact.id) ? "bookmark.fill" : "bookmark",
                isActive: viewModel.isSaved(fact.id),
                isEnabled: true
            ) {
                viewModel.toggleSave(fact)
            }

            LiquidIconButton(
                systemName: "sparkles",
                isActive: viewModel.isHearted(fact.id),
                isEnabled: true
            ) {
                Task { await viewModel.heartFact(fact) }
            }

            FactShareLink(fact: fact, compact: compact)
                .background(Circle().fill(AppTheme.accentSoft))

            if showReadMore, let url = fact.pageURL {
                Link(destination: url) {
                    Label(
                        isFlipped ? "Read full article" : "Read more",
                        systemImage: "arrow.up.right"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isFlipped ? .white : AppTheme.accent)
                    .padding(.horizontal, isFlipped ? 16 : 14)
                    .frame(height: compact ? 40 : 44)
                }
                .background(Capsule().fill(isFlipped ? AppTheme.accent : AppTheme.accentSoft))
                .shadow(color: isFlipped ? AppTheme.accent.opacity(0.35) : .clear, radius: 8, y: 2)
                .animation(.easeInOut(duration: 0.25), value: isFlipped)
            }

            Spacer(minLength: 0)
        }
    }
}
