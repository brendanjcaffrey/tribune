import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let dismissButton = UIButton(type: .system)
    private let card = UIStackView()

    private static let maxCardWidth: CGFloat = 340
    private static let cardInset: CGFloat = 24

    private let successLinger = Duration.milliseconds(900)

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Task {
            do {
                let page = try await extractPage()
                let id = try await PageUpload.push(page)
                await finish(page: page, id: id)
            } catch {
                fail(error)
            }
        }
    }

    // safari runs page.js in the tab and hands the result back as a plist
    // attachment. no attachment means it was something other than a web page.
    private func extractPage() async throws -> Page {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        let type = UTType.propertyList.identifier

        for provider in providers where provider.hasItemConformingToTypeIdentifier(type) {
            let loaded = try? await provider.loadItem(forTypeIdentifier: type)
            let results = (loaded as? [String: Any])?[NSExtensionJavaScriptPreprocessingResultsKey]
            if let page = Page(javaScriptResults: results) { return page }
        }

        throw ShareError.noPage
    }

    private func finish(page: Page, id: Int) async {
        print("pushed \(page.url) to tribune as newsletter \(id) with \(page.images.count) images")

        spinner.stopAnimating()
        // the server downloads whatever the page wouldn't hand over, so no
        // images is a slower push rather than a worse one
        switch page.images.count {
        case 0: statusLabel.text = "Pushed to Tribune"
        case 1: statusLabel.text = "Pushed to Tribune\n1 image sent"
        case let count: statusLabel.text = "Pushed to Tribune\n\(count) images sent"
        }

        // long enough to read, short enough that it doesn't feel like a step
        try? await Task.sleep(for: successLinger)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func fail(_ error: Error) {
        print("push to tribune failed: \(error)")

        spinner.stopAnimating()
        statusLabel.text = error.localizedDescription
        dismissButton.isHidden = false
    }

    private func buildInterface() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.25)

        card.axis = .vertical
        card.alignment = .center
        card.spacing = 12
        card.isLayoutMarginsRelativeArrangement = true
        card.layoutMargins = UIEdgeInsets(top: Self.cardInset, left: Self.cardInset,
                                          bottom: Self.cardInset, right: Self.cardInset)
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 18
        card.translatesAutoresizingMaskIntoConstraints = false

        spinner.startAnimating()

        statusLabel.text = "Pushing to Tribune…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .body)

        dismissButton.setTitle("Dismiss", for: .normal)
        dismissButton.isHidden = true
        dismissButton.addTarget(self, action: #selector(dismissShare), for: .touchUpInside)

        card.addArrangedSubview(spinner)
        card.addArrangedSubview(statusLabel)
        card.addArrangedSubview(dismissButton)
        view.addSubview(card)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maxCardWidth),
            // the stack sizes itself off its widest child, so the label needs a
            // ceiling of its own or a long server error grows the card instead
            // of wrapping inside it
            statusLabel.widthAnchor.constraint(
                lessThanOrEqualToConstant: Self.maxCardWidth - Self.cardInset * 2)
        ])
    }

    @objc private func dismissShare() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
