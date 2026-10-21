import SwiftUI

/// Tappable fact card: front = bite-size fact; back = richer Wikipedia detail.
struct FactCard: View {
    let fact: Fact
    var statusMessage: String? = nil
    var isFlipped: Bool = false
    var detail: FactDetail? = nil
    var isLoadingDetail: Bool = false
    var detailFailed: Bool = false
    var onFlip: (() -> Void)? = nil

    var body: some View {
        // Only the visible face is in the hierarchy, so height fits that side
        // (Saved list no longer leaves empty gaps under short fronts).
        Group {
            if isFlipped {
                cardBack
            } else {
                cardFront
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.35), value: isFlipped)
        .onTapGesture {
            onFlip?()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isFlipped ? "Shows the short fact again" : "Shows more detail from Wikipedia")
        .accessibilityLabel(isFlipped ? "A closer look at \(fact.title)" : "Fact card for \(fact.title)")
    }

    private var cardFront: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let imageURL = fact.imageURL {
                // Color.clear + overlay keeps scaledToFill from widening the whole card.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .overlay {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                EmptyView()
                            default:
                                AppTheme.accentSoft
                                    .overlay { ProgressView().tint(AppTheme.accent) }
                            }
                        }
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Text(fact.title)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !fact.summary.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(frontSummaryChunks.enumerated()), id: \.offset) { _, chunk in
                        Text(chunk)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(AppTheme.inkSoft)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if !fact.highlight.isEmpty {
                Text(fact.highlight)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(AppTheme.accent)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(sourceLine)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Tap for a closer look", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(cardStroke(AppTheme.line))
    }

    private var cardBack: some View {
        VStack(alignment: .leading, spacing: 0) {
            backHeader

            VStack(alignment: .leading, spacing: 18) {
                Text(fact.title)
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let detail, !detail.shortDescription.isEmpty {
                    Text(detail.shortDescription)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isLoadingDetail && detail == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(AppTheme.accent)
                        Text("Pulling a deeper read…")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.vertical, 8)
                } else if let detail {
                    backDetailContent(detail)
                } else if detailFailed {
                    Text("Couldn’t load more detail for this page. Use Read more on the bar to open Wikipedia.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accentSoft.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(cardStroke(AppTheme.accent.opacity(0.28)))
    }

    private var backHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Read more")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Spacer(minLength: 8)
            Label("Flip back", systemImage: "arrow.uturn.backward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.surface.opacity(0.9))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accent.opacity(0.10))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.accent.opacity(0.18))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func backDetailContent(_ detail: FactDetail) -> some View {
        let blocks = backBlocks(from: detail)

        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .heading(let title):
                        Text(title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .body(let text):
                        Text(text)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(AppTheme.inkSoft)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        } else {
            Text("Nothing extra beyond the short fact on the front. Open Wikipedia from the bar for the full article.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !detail.categories.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Related topics")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 4)
                CategoryChipWrap(categories: detail.categories)
            }
        }

        Text(backFooter)
            .font(.caption)
            .foregroundStyle(AppTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    private var frontSummaryChunks: [String] {
        TextUtils.readableChunks(from: fact.summary, preferredMaxChars: 220)
    }

    private var frontPieces: [String] {
        [fact.summary, fact.highlight].filter { !$0.isEmpty }
    }

    /// One full closer-look section (prefers Early life / Background), never front copy.
    private func backBlocks(from detail: FactDetail) -> [TextUtils.ArticleBlock] {
        TextUtils.closerLookBlocks(
            from: detail.longExtract,
            frontPieces: frontPieces,
            preferredMaxChars: 280
        )
    }

    private func cardStroke(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(color, lineWidth: 1)
    }

    private var sourceLine: String {
        switch fact.source {
        case .random, .dyk:
            return "Source: Wikipedia · Did you know"
        case .list:
            return "Source: Wikipedia list · Read more opens the full list"
        case .search:
            return "Source: Wikipedia · matched to your interests"
        }
    }

    private var backFooter: String {
        switch fact.source {
        case .list:
            return "Showing one full section from the related article. Read more opens the Wikipedia list."
        default:
            return "One full Wikipedia section (Early life when available). Read more opens the rest."
        }
    }
}

private struct CategoryChipWrap: View {
    let categories: [String]

    var body: some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(categories, id: \.self) { category in
                Text(category)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.inkSoft)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.surface.opacity(0.92))
                    .clipShape(Capsule())
            }
        }
    }
}

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var height: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            height = max(height, y + size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
