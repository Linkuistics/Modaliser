/// DP-based fuzzy string matcher inspired by fzf/fzy.
///
/// Finds the optimal alignment of query characters in a target string, maximizing:
/// - Consecutive character runs (compounding bonus)
/// - Word boundary matches (/, space, -, _, ., camelCase transitions)
/// - Start-of-string matches
///
/// Penalizes gaps between matched characters. Returns matched character indices
/// for highlighting and a last-match-index for tail proximity scoring.
enum FuzzyMatcher {

    struct MatchResult {
        let score: Int
        let matchedIndices: Set<Int>
        let lastMatchIndex: Int
    }

    // MARK: - Scoring constants (fzf-inspired)

    private static let matchBase = 16
    private static let gapPenalty = -3
    private static let consecutiveBonus = 4
    private static let minScore = Int.min / 2

    /// Match query against target using DP-based fuzzy matching.
    /// Query is matched case-insensitively. Returns nil if no match is possible.
    static func match(query: String, target: String) -> MatchResult? {
        guard !query.isEmpty else { return MatchResult(score: 1, matchedIndices: [], lastMatchIndex: -1) }

        let queryChars = Array(query.lowercased())
        let targetOriginal = Array(target)
        let targetLower = Array(target.lowercased())
        let n = queryChars.count
        let m = targetLower.count
        guard n <= m else { return nil }

        // Quick existence check: greedy forward scan
        var qi = 0
        for ch in targetLower {
            if qi < n && ch == queryChars[qi] { qi += 1 }
        }
        guard qi == n else { return nil }

        // Precompute position bonuses for word boundaries
        let bonus = computePositionBonuses(original: targetOriginal)

        // DP with flat arrays: M[i*m+j] and D[i*m+j]
        // M = best score matching query[0..i] ending at target[j]
        // D = same but with target[j-1] matching query[i-1] (consecutive path)
        let size = n * m
        var bestScores = [Int](repeating: minScore, count: size)
        var consecutiveScores = [Int](repeating: minScore, count: size)
        var tracebackPositions = [Int](repeating: -1, count: size)

        // Row 0: first query character
        for j in 0..<m where targetLower[j] == queryChars[0] {
            bestScores[j] = matchBase + bonus[j]
            consecutiveScores[j] = bestScores[j]
        }

        // Rows 1..n-1
        for i in 1..<n {
            var bestPrevScore = minScore
            var bestPrevPosition = -1
            let row = i * m
            let prevRow = (i - 1) * m

            for j in i..<m {
                // Track running max of previous row for gap path
                if j > 0 && bestScores[prevRow + j - 1] > bestPrevScore {
                    bestPrevScore = bestScores[prevRow + j - 1]
                    bestPrevPosition = j - 1
                }

                guard targetLower[j] == queryChars[i] else { continue }

                let positionBonus = bonus[j]

                // Consecutive path: query[i-1] matched at target[j-1]
                var dScore = minScore
                if j > 0 {
                    let prevBest = bestScores[prevRow + j - 1]
                    let prevConsecutive = consecutiveScores[prevRow + j - 1]
                    if prevConsecutive > minScore {
                        dScore = prevConsecutive + matchBase + max(positionBonus, consecutiveBonus)
                    }
                    if prevBest > minScore {
                        dScore = max(dScore, prevBest + matchBase + positionBonus)
                    }
                }
                consecutiveScores[row + j] = dScore

                // Gap path: best M[i-1][k] for k < j, plus gap penalty
                let gScore = bestPrevScore > minScore
                    ? bestPrevScore + gapPenalty + matchBase + positionBonus
                    : minScore

                if dScore >= gScore && dScore > minScore {
                    bestScores[row + j] = dScore
                    tracebackPositions[row + j] = j - 1
                } else if gScore > minScore {
                    bestScores[row + j] = gScore
                    tracebackPositions[row + j] = bestPrevPosition
                }
            }
        }

        // Find best ending position in last row
        var finalScore = minScore
        var finalPosition = -1
        let lastRow = (n - 1) * m
        for j in (n - 1)..<m {
            if bestScores[lastRow + j] > finalScore {
                finalScore = bestScores[lastRow + j]
                finalPosition = j
            }
        }
        guard finalScore > minScore, finalPosition >= 0 else { return nil }

        // Traceback to recover matched character positions
        var matched = Set<Int>()
        var j = finalPosition
        for i in stride(from: n - 1, through: 0, by: -1) {
            matched.insert(j)
            if i > 0 { j = tracebackPositions[i * m + j] }
        }

        return MatchResult(score: finalScore, matchedIndices: matched, lastMatchIndex: finalPosition)
    }

    // MARK: - Position bonus computation

    /// Compute word boundary bonuses for each position in the target string.
    /// Higher bonuses at word starts (after separators, camelCase transitions).
    private static func computePositionBonuses(original: [Character]) -> [Int] {
        var bonus = [Int](repeating: 0, count: original.count)
        for j in 0..<original.count {
            if j == 0 {
                bonus[j] = 10  // Start of string
            } else {
                let prev = original[j - 1]
                if prev == "/" || prev == "\\" { bonus[j] = 9 }
                else if prev == " " || prev == "\t" { bonus[j] = 10 }
                else if prev == "-" || prev == "_" { bonus[j] = 8 }
                else if prev == "." { bonus[j] = 7 }
                else if prev.isLowercase && original[j].isUppercase { bonus[j] = 7 }
            }
        }
        return bonus
    }
}
