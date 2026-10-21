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
        ZStack {
            cardFront
                .opacity(isFlipped ? 0 : 1)
                .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .accessibilityHidden(isFlipped)
                .allowsHitTesting(!isFlipped)

            cardBack
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .accessibilityHidden(!isFlipped)
                .allowsHitTesting(isFlipped)
        }
        .animation(.easeInOut(duration: 0.45), value: isFlipped)
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
                .frame(maxWidth: .infinity, alignment: .leading)

            if !fact.summary.isEmpty {
                Text(fact.summary)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(AppTheme.inkSoft)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !fact.highlight.isEmpty {
                Text(fact.highlight)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(AppTheme.accent)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(alignment: .firstTextBaseline) {
                Text(sourceLine)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                Spacer(minLength: 8)
                Label("Tap for a closer look", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(cardStroke(AppTheme.line))
        .clipped()
    }

    private var cardBack: some View {
        VStack(alignment: .leading, spacing: 0) {
            backHeader

            VStack(alignment: .leading, spacing: 16) {
                Text(fact.title)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isLoadingDetail && detail == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(AppTheme.accent)
                        Text("Pulling a deeper read…")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.vertical, 12)
                } else if let detail {
                    backDetailContent(detail)
                } else if detailFailed {
                    Text("Couldn’t load more detail for this page. Use Read more to open Wikipedia.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }

                Text(backFooter)
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accentSoft.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(cardStroke(AppTheme.accent.opacity(0.28)))
        .clipped()
    }

    private var backHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("A closer look")
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("Beyond the short fact")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
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
        let extraParagraphs = backParagraphs(from: detail)

        if !detail.shortDescription.isEmpty {
            Text(detail.shortDescription)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !extraParagraphs.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(extraParagraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(AppTheme.inkSoft)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, detail.shortDescription.isEmpty ? 0 : 2)
        } else {
            Text("No extra paragraphs beyond what you already saw. Categories below may still help — or open Wikipedia for the full article.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
        }

        if !detail.categories.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Related categories")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                CategoryChipWrap(categories: detail.categories)
            }
            .padding(.top, 4)
        }
    }

    /// Back copy with the front summary/highlight removed, split into airy paragraphs.
    private func backParagraphs(from detail: FactDetail) -> [String] {
        let stripped = TextUtils.stripFrontOverlap(
            from: detail.longExtract,
            frontPieces: [fact.summary, fact.highlight]
        )
        let paragraphs = TextUtils.paragraphs(from: stripped)
        // Keep the back scannable — don't dump a novel.
        return Array(paragraphs.prefix(4))
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
            return "In-app detail is from the related article. Read more opens the full Wikipedia list."
        default:
            return "In-app deeper read. Read more opens the full Wikipedia article."
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
