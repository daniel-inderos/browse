import SwiftUI
import Combine

@MainActor
@Observable
final class IntentBarViewModel {
    var text: String = "" {
        didSet { scheduleClassification() }
    }
    var liveClassification: IntentClassification?
    var isExpanded: Bool = false

    private let classifier = IntentClassifier()
    private var classificationTask: Task<Void, Never>?
    private var modeOverride: ModeOverride?

    func submit() -> IntentClassification {
        let classification = classifyForCurrentMode(text)
        text = ""
        modeOverride = nil
        liveClassification = nil
        return classification
    }

    func setURLDisplay(_ url: URL?) {
        modeOverride = nil
        if let url {
            text = url.absoluteString
            liveClassification = .open(url)
        }
    }

    @discardableResult
    func toggleSearchBriefMode(text currentText: String? = nil) -> Bool {
        if let currentText {
            text = currentText
        }

        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        guard case .open = classifier.classify(text) else {
            switch classifyForCurrentMode(text) {
            case .brief:
                modeOverride = .search
                liveClassification = .search(query: query)
            case .search:
                modeOverride = .brief
                liveClassification = .brief(query: query)
            case .open:
                return false
            }
            return true
        }

        return false
    }

    private func scheduleClassification() {
        classificationTask?.cancel()
        classificationTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            if text.isEmpty {
                modeOverride = nil
                liveClassification = nil
            } else {
                liveClassification = classifyForCurrentMode(text)
            }
        }
    }

    private func classifyForCurrentMode(_ input: String) -> IntentClassification {
        let classification = classifier.classify(input)
        guard let modeOverride else { return classification }

        switch classification {
        case .open:
            return classification
        case .brief(let query), .search(let query):
            switch modeOverride {
            case .brief:
                return .brief(query: query)
            case .search:
                return .search(query: query)
            }
        }
    }

    private enum ModeOverride {
        case brief
        case search
    }
}
