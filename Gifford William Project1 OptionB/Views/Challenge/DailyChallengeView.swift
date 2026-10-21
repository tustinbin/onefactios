import SwiftUI

struct DailyChallengeView: View {
    @ObservedObject var viewModel: OneFactViewModel
    /// Smooth bar fill (0…total); eases toward each loaded-fact milestone.
    @State private var animatedLoadProgress: Double = 0

    var body: some View {
        Group {
            switch viewModel.challengePhase {
            case .intro:
                introPhase
            case .loading:
                loadingPhase
            case .reading:
                readingPhase
            case .quiz:
                quizPhase
            case .results:
                resultsPhase
            }
        }
        .background(AppTheme.paperGradient.ignoresSafeArea())
        .onChange(of: viewModel.challengePhase) { _, phase in
            if phase == .loading {
                animatedLoadProgress = 0
            }
        }
        .onChange(of: viewModel.challengeLoadProgress) { _, newValue in
            withAnimation(.easeInOut(duration: 0.85)) {
                animatedLoadProgress = Double(newValue)
            }
        }
        .task(id: viewModel.challengePhase) {
            guard viewModel.challengePhase == .loading else { return }
            let total = Double(max(viewModel.challengeLoadTotal, 1))
            while !Task.isCancelled, viewModel.challengePhase == .loading {
                try? await Task.sleep(nanoseconds: 50_000_000)
                let loaded = Double(viewModel.challengeLoadProgress)
                let ceiling = min(loaded + 0.92, total - 0.02)
                guard animatedLoadProgress < ceiling else { continue }
                withAnimation(.linear(duration: 0.05)) {
                    animatedLoadProgress = min(animatedLoadProgress + 0.035, ceiling)
                }
            }
        }
        .sheet(isPresented: $viewModel.showHeartSheet) {
            HeartSuggestionsSheet(viewModel: viewModel)
        }
    }

    // MARK: - Intro

    private var introPhase: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(
                    title: "Challenge",
                    subtitle: "A short practice session — five facts, then a quick recall: titles you saw, excerpt matches, and (when there’s a photo) which article an image belongs to."
                )

                VStack(alignment: .leading, spacing: 10) {
                    Label("\(DailyChallengeState.deckSize) facts with flip detail", systemImage: "rectangle.on.rectangle.angled")
                    Label("Previous / Next through the session", systemImage: "arrow.left.arrow.right")
                    Label(
                        "\(DailyChallengeState.recognitionQuizCount) recall + \(DailyChallengeState.excerptQuizCount) excerpts + image match when available",
                        systemImage: "questionmark.circle"
                    )
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.inkSoft)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Session source")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Picker("Session source", selection: $viewModel.challengeDeckMode) {
                        ForEach(FactMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.challengeDeckMode == .interests, !viewModel.canStartInterestChallenge {
                        Text("Select at least one niche in Interests to use this mode.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }

                if let challenge = viewModel.dailyChallenge, !challenge.deck.isEmpty {
                    Text(
                        challenge.quizDone
                            ? "Last session finished — \(challenge.quizScore)/\(max(challenge.quizTotal, 1)). Start a new one anytime."
                            : "In progress · \(challenge.progressLabel)"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                }

                PrimaryButton(title: "Start new session") {
                    viewModel.startNewChallenge()
                }
                .opacity(
                    viewModel.challengeDeckMode == .interests && !viewModel.canStartInterestChallenge
                        ? 0.5 : 1
                )

                if viewModel.hasResumableChallenge {
                    Button {
                        viewModel.resumeChallenge()
                    } label: {
                        Text("Continue current session")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                if viewModel.hasChallengeResults {
                    Button {
                        viewModel.viewChallengeResults()
                    } label: {
                        Text("View last results")
                            .font(.system(.body, design: .rounded).weight(.medium))
                            .foregroundStyle(AppTheme.accent)
                    }
                }

                recentSessionsSection
            }
            .padding(20)
            .padding(.bottom, 8)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var recentSessionsSection: some View {
        let sessions = viewModel.challengeHistory
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent sessions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .padding(.top, 8)

            if sessions.isEmpty {
                Text("Finished quizzes show up here — a quick trail of scores as you practice.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.line, lineWidth: 1)
                    )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(sessions) { session in
                        ChallengeSessionRow(session: session)
                        if session.id != sessions.last?.id {
                            Divider().background(AppTheme.line)
                        }
                    }
                }
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.line, lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Loading

    private var loadingPhase: some View {
        let total = Double(max(viewModel.challengeLoadTotal, 1))
        return VStack(spacing: 16) {
            ProgressView()
                .tint(AppTheme.accent)
            Text("Building your session…")
                .font(.system(.title3, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text("\(viewModel.challengeLoadProgress) / \(viewModel.challengeLoadTotal)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

            GeometryReader { geo in
                let fraction = min(max(animatedLoadProgress / total, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.accentSoft)
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 8 : 0))
                }
            }
            .frame(maxWidth: 240, minHeight: 10, maxHeight: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Reading

    private var readingPhase: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(readingTopicLabel)
                            .font(.caption.weight(.semibold))
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(2)
                        Spacer()
                        Text(viewModel.dailyChallenge?.progressLabel ?? "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }

                    if let fact = viewModel.challengeFact {
                        FactCard(
                            fact: fact,
                            isFlipped: viewModel.challengeFlipped,
                            detail: viewModel.challengeDetail,
                            isLoadingDetail: viewModel.challengeDetailLoading,
                            detailFailed: viewModel.challengeDetailFailed,
                            onFlip: { viewModel.toggleChallengeCardFlip() }
                        )
                    }
                }
                .padding(20)
                .padding(.bottom, 8)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LiquidGlassBar {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            viewModel.challengeGoPrevious()
                        } label: {
                            Label("Previous", systemImage: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(AppTheme.inkSoft)
                                .background(AppTheme.accentSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled((viewModel.dailyChallenge?.index ?? 0) <= 0)
                        .opacity((viewModel.dailyChallenge?.index ?? 0) <= 0 ? 0.45 : 1)

                        Button {
                            viewModel.challengeGoNext()
                        } label: {
                            let isLast = viewModel.dailyChallenge.map {
                                $0.index >= max($0.orderedDeck.count - 1, 0)
                            } ?? true
                            Label(
                                isLast ? "Quick check" : "Next",
                                systemImage: isLast ? "questionmark.circle" : "chevron.right"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(AppTheme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if let fact = viewModel.challengeFact {
                        FactActionToolbar(
                            fact: fact,
                            viewModel: viewModel,
                            isFlipped: viewModel.challengeFlipped
                        )
                    }

                    HStack {
                        Button("Skip to check") {
                            viewModel.beginChallengeQuiz()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)

                        Spacer()

                        Button("Exit") {
                            viewModel.challengePhase = .intro
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var readingTopicLabel: String {
        if let fact = viewModel.challengeFact,
           let niche = viewModel.challengeTopicLabel(for: fact) {
            return niche
        }
        return "Challenge"
    }

    // MARK: - Quiz

    private var quizPhase: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Quick check")
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .foregroundStyle(AppTheme.ink)

                    if viewModel.quizQuestions.indices.contains(viewModel.quizIndex) {
                        let question = viewModel.quizQuestions[viewModel.quizIndex]
                        let answered = viewModel.quizSelectedOption != nil
                        let selected = viewModel.quizSelectedOption
                        let isCorrect = selected == question.correctIndex

                        Text("Question \(viewModel.quizIndex + 1) of \(viewModel.quizQuestions.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)

                        Text(question.prompt)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        if let excerpt = question.excerpt {
                            Text(excerpt)
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(AppTheme.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.accentSoft.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if let imageURL = question.imageURL {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .overlay {
                                    AsyncImage(url: imageURL) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        case .failure:
                                            AppTheme.accentSoft
                                                .overlay {
                                                    Text("Image unavailable")
                                                        .font(.caption)
                                                        .foregroundStyle(AppTheme.muted)
                                                }
                                        default:
                                            AppTheme.accentSoft
                                                .overlay { ProgressView().tint(AppTheme.accent) }
                                        }
                                    }
                                }
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                            Button {
                                viewModel.selectQuizOption(index)
                            } label: {
                                quizOptionRow(
                                    option: option,
                                    index: index,
                                    question: question,
                                    answered: answered,
                                    selected: selected
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(answered)
                        }

                        if answered {
                            Text(isCorrect
                                 ? "Correct"
                                 : "Not quite — it was “\(question.options[question.correctIndex])”")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isCorrect ? AppTheme.success : AppTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            LiquidGlassBar {
                PrimaryButton(
                    title: viewModel.quizIndex + 1 >= viewModel.quizQuestions.count
                        ? "Finish" : "Next question"
                ) {
                    viewModel.submitQuizAnswerAndAdvance()
                }
                .opacity(viewModel.quizHasAnsweredCurrent ? 1 : 0.5)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func quizOptionRow(
        option: String,
        index: Int,
        question: QuizQuestion,
        answered: Bool,
        selected: Int?
    ) -> some View {
        let isSelected = selected == index
        let isCorrectOption = index == question.correctIndex
        let style = quizOptionStyle(
            answered: answered,
            isSelected: isSelected,
            isCorrectOption: isCorrectOption
        )

        return HStack {
            Image(systemName: style.icon)
            Text(option)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(style.foreground)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style.stroke, lineWidth: style.strokeWidth)
        )
    }

    private func quizOptionStyle(
        answered: Bool,
        isSelected: Bool,
        isCorrectOption: Bool
    ) -> (icon: String, foreground: Color, background: Color, stroke: Color, strokeWidth: CGFloat) {
        if !answered {
            return (
                isSelected ? "checkmark.circle.fill" : "circle",
                isSelected ? .white : AppTheme.inkSoft,
                isSelected ? AppTheme.accent : AppTheme.accentSoft,
                .clear,
                0
            )
        }
        if isCorrectOption {
            return ("checkmark.circle.fill", AppTheme.success, AppTheme.successSoft, AppTheme.success.opacity(0.35), 1.5)
        }
        if isSelected {
            return ("xmark.circle.fill", AppTheme.danger, AppTheme.danger.opacity(0.12), AppTheme.danger.opacity(0.35), 1.5)
        }
        return ("circle", AppTheme.muted, AppTheme.accentSoft.opacity(0.5), .clear, 0)
    }

    // MARK: - Results

    private var resultsPhase: some View {
        Group {
            if let fact = viewModel.selectedChallengeReviewFact {
                challengeReviewDetail(fact)
            } else {
                resultsList
            }
        }
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(
                    title: "Session complete",
                    subtitle: "Nice work. Tap a fact to open it again — save, share, or find related niches."
                )

                if let challenge = viewModel.dailyChallenge {
                    if challenge.quizTotal > 0 {
                        Text("Score \(challenge.quizScore) / \(challenge.quizTotal)")
                            .font(.system(.title, design: .serif).weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                    } else {
                        Text("\(challenge.deck.count) facts in this session")
                            .font(.system(.title3, design: .serif).weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                    }

                    let facts = challenge.orderedDeck
                    if !facts.isEmpty {
                        Text("Facts in this session")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.top, 4)

                        LazyVStack(spacing: 0) {
                            ForEach(facts) { fact in
                                Button {
                                    viewModel.openChallengeReviewFact(fact)
                                } label: {
                                    ChallengeFactRow(
                                        fact: fact,
                                        nicheLabel: viewModel.challengeTopicLabel(for: fact)
                                    )
                                }
                                .buttonStyle(.plain)

                                if fact.id != facts.last?.id {
                                    Divider().background(AppTheme.line)
                                }
                            }
                        }
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppTheme.line, lineWidth: 1)
                        )
                    }
                }

                Button {
                    viewModel.retakeChallengeQuiz()
                } label: {
                    Text("Retake quick check")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }

                Button {
                    viewModel.selectedChallengeReviewID = nil
                    viewModel.challengePhase = .intro
                } label: {
                    Text("Start another session")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(20)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func challengeReviewDetail(_ fact: Fact) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    viewModel.closeChallengeReviewFact()
                } label: {
                    Label("Back to session", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.accentSoft)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                if let niche = viewModel.challengeTopicLabel(for: fact) {
                    Text(niche)
                        .font(.caption.weight(.semibold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(AppTheme.muted)
                }

                FactCard(
                    fact: fact,
                    isFlipped: viewModel.challengeFlipped,
                    detail: viewModel.challengeDetail,
                    isLoadingDetail: viewModel.challengeDetailLoading,
                    detailFailed: viewModel.challengeDetailFailed,
                    onFlip: { viewModel.toggleChallengeReviewCardFlip() }
                )

                FactActionToolbar(
                    fact: fact,
                    viewModel: viewModel,
                    isFlipped: viewModel.challengeFlipped,
                    compact: true
                )
            }
            .padding(20)
            .padding(.bottom, 8)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(AppTheme.ink)
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(AppTheme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ChallengeSessionRow: View {
    let session: ChallengeSessionRecord

    private var dateLabel: String {
        session.finishedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var preview: String {
        let titles = session.titles.prefix(2)
        guard !titles.isEmpty else { return session.mode.label }
        return titles.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.scoreLabel)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("\(session.mode.label) · \(dateLabel)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(AppTheme.inkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: session.score == session.total && session.total > 0
                  ? "star.fill" : "checkmark.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(session.score == session.total && session.total > 0
                                 ? AppTheme.accent : AppTheme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct ChallengeFactRow: View {
    let fact: Fact
    var nicheLabel: String? = nil

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
                        Image(systemName: "flame.fill")
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
                if let nicheLabel {
                    Text(nicheLabel)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
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
