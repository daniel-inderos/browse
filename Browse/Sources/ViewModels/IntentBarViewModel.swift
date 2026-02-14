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

    func submit() -> IntentClassification {
        let classification = classifier.classify(text)
        text = ""
        liveClassification = nil
        return classification
    }

    func setURLDisplay(_ url: URL?) {
        if let url {
            text = url.absoluteString
            liveClassification = .open(url)
        }
    }

    private func scheduleClassification() {
        classificationTask?.cancel()
        classificationTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            if text.isEmpty {
                liveClassification = nil
            } else {
                liveClassification = classifier.classify(text)
            }
        }
    }
}
