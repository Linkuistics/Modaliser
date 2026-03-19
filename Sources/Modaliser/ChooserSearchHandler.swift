import AppKit

/// Search field delegation and choice filtering for the chooser.
/// Note: The DP-based fuzzy matcher is deferred to Session 6.
/// For now, uses simple case-insensitive substring matching.
extension ChooserWindowController: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        guard !actionPanel.isActive else { return }
        guard let sf = searchField else { return }
        filterChoices(query: sf.stringValue)
    }

    func filterChoices(query: String) {
        if query.isEmpty {
            filteredChoices = choices
            filteredTextMatches = Array(repeating: [], count: choices.count)
            filteredSubMatches = Array(repeating: [], count: choices.count)
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

    /// Runs search on the background queue, dispatches results to main thread.
    /// Uses simple substring matching for now — Session 6 adds DP fuzzy matching.
    private func performSearch(query: String, choices: [ChooserChoice], generation: Int) {
        let q = query.lowercased()
        var scored: [(index: Int, score: Int, textMatches: Set<Int>, subMatches: Set<Int>)] = []

        for (idx, choice) in choices.enumerated() {
            let textMatch = substringMatch(query: q, target: choice.text)
            let subMatch = choice.subText.flatMap { substringMatch(query: q, target: $0) }

            let textScore = textMatch?.score ?? 0
            let subScore = subMatch?.score ?? 0

            if textScore > 0 && textScore >= subScore {
                scored.append((idx, textScore, textMatch!.indices, []))
            } else if subScore > 0 {
                scored.append((idx, subScore, [], subMatch!.indices))
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

    /// Simple case-insensitive substring match. Returns match score and indices.
    /// Placeholder until Session 6's DP fuzzy matcher.
    private func substringMatch(query: String, target: String) -> (score: Int, indices: Set<Int>)? {
        let tLow = target.lowercased()
        guard let range = tLow.range(of: query) else { return nil }
        let startIdx = tLow.distance(from: tLow.startIndex, to: range.lowerBound)
        let indices = Set(startIdx..<(startIdx + query.count))
        // Score: prefer matches at the start
        let positionBonus = startIdx == 0 ? 100 : 50
        return (positionBonus + query.count * 10, indices)
    }
}
