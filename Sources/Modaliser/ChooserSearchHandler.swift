import AppKit

/// Search field delegation and choice filtering for the chooser.
/// Uses FuzzyMatcher for DP-based fuzzy matching with word boundary bonuses.
extension ChooserWindowController: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        guard !actionPanel.isActive else { return }
        guard let sf = searchField else { return }
        filterChoices(query: sf.stringValue)
    }

    func filterChoices(query: String) {
        if query.isEmpty {
            filteredChoices = searchMode == .showAll ? choices : []
            let matchCount = filteredChoices.count
            filteredTextMatches = Array(repeating: [], count: matchCount)
            filteredSubMatches = Array(repeating: [], count: matchCount)
            selectedIndex = 0
            resizeTableArea()
            tableView?.reloadData()
            scrollToSelected()
        } else {
            // Debounced background search
            searchDebounce?.cancel()
            let gen = searchGeneration + 1
            searchGeneration = gen
            let choicesCopy = choices
            let work = DispatchWorkItem { [weak self] in
                self?.performSearch(query: query, choices: choicesCopy, generation: gen)
            }
            searchDebounce = work
            searchQueue.asyncAfter(deadline: .now() + 0.03, execute: work)
        }
    }

    /// Runs fuzzy matching on the background search queue, dispatches results to main thread.
    /// Path-aware: "/" in query enables subText matching with tail proximity bonus.
    private func performSearch(query: String, choices: [ChooserChoice], generation: Int) {
        let queryHasSlash = query.contains("/")
        var scored: [(index: Int, score: Int, textMatches: Set<Int>, subMatches: Set<Int>)] = []

        for (idx, choice) in choices.enumerated() {
            let textMatch = FuzzyMatcher.match(query: query, target: choice.text)

            let subMatch: FuzzyMatcher.MatchResult?
            if queryHasSlash, let sub = choice.subText {
                subMatch = FuzzyMatcher.match(query: query, target: sub)
            } else {
                subMatch = nil
            }

            let textScore = textMatch?.score ?? 0
            var subScore = subMatch?.score ?? 0

            // Tail proximity bonus for path matches: prefer matches near end of path
            if subScore > 0, let sub = choice.subText, let sm = subMatch {
                let charsAfterMatch = sub.count - sm.lastMatchIndex - 1
                subScore += max(0, 30 - charsAfterMatch)
            }

            if textScore > 0 && textScore >= subScore {
                scored.append((idx, textScore, textMatch!.matchedIndices, []))
            } else if subScore > 0 {
                scored.append((idx, subScore, [], subMatch!.matchedIndices))
            }
        }
        scored.sort { $0.score > $1.score }

        let resultChoices = scored.map { choices[$0.index] }
        let resultTextM = scored.map { $0.textMatches }
        let resultSubM = scored.map { $0.subMatches }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.searchGeneration == generation else { return }
            self.filteredChoices = resultChoices
            self.filteredTextMatches = resultTextM
            self.filteredSubMatches = resultSubM
            self.selectedIndex = 0
            self.resizeTableArea()
            self.tableView?.reloadData()
            self.scrollToSelected()
        }
    }
}
