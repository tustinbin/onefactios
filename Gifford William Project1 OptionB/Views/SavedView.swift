import SwiftUI

struct SavedView: View {
    @ObservedObject var viewModel: OneFactViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Saved facts")
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(viewModel.saved.isEmpty
                         ? "Facts you keep for later."
                         : "\(viewModel.saved.count) saved — tap Read more anytime.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                }

                if viewModel.saved.isEmpty {
                    Text("Save a fact from Learn to build this list.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .padding(.vertical, 24)
                } else {
                    ForEach(viewModel.saved) { fact in
                        SavedFactRow(fact: fact) {
                            viewModel.removeSaved(fact.id)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.paperGradient.ignoresSafeArea())
    }
}

private struct SavedFactRow: View {
    let fact: Fact
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(fact.title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !fact.summary.isEmpty {
                Text(fact.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if let url = fact.pageURL {
                    Link("Read more", destination: url)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                Spacer()
                Button("Remove", action: onRemove)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.danger)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1)
        )
    }
}
