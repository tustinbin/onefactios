import LinkPresentation
import SwiftUI
import UIKit

/// Opens the system share sheet with a single activity item source.
/// Passing both a raw `URL` and `String` makes many destinations (Messages, Mail)
/// disappear — extensions only appear if they accept *every* item.
struct FactShareLink: View {
    let fact: Fact
    var compact: Bool = false

    var body: some View {
        Button {
            presentSystemShare()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.inkSoft)
                .frame(width: compact ? 40 : 44, height: compact ? 40 : 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share fact")
    }

    private func presentSystemShare() {
        let activity = UIActivityViewController(
            activityItems: [FactActivityItem(fact: fact)],
            applicationActivities: nil
        )
        // Reading List only applies to bare URLs and crowds out messaging apps.
        activity.excludedActivityTypes = [.addToReadingList]

        guard let presenter = topViewController() else { return }

        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }

        presenter.present(activity, animated: true)
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

/// One item that reports as text (so Messages / Mail appear), with a subject + link preview.
private final class FactActivityItem: NSObject, UIActivityItemSource {
    let fact: Fact

    init(fact: Fact) {
        self.fact = fact
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        // Placeholder type decides which destinations are offered. Must be String.
        fact.shareText
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        switch activityType {
        case .mail, .message, .copyToPasteboard, .postToTwitter, .postToFacebook:
            return fact.shareText
        case .airDrop:
            return fact.pageURL ?? fact.shareText
        default:
            return fact.shareText
        }
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        fact.shareSubject
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = fact.title
        if let pageURL = fact.pageURL {
            metadata.originalURL = pageURL
            metadata.url = pageURL
        }
        return metadata
    }
}
