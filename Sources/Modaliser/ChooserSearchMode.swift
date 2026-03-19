/// Controls whether the chooser shows all items on open or requires a query first.
enum ChooserSearchMode {
    /// Empty query shows all choices (e.g., app selectors, window selectors).
    case showAll
    /// Empty query shows nothing — user must type to see results (e.g., file search).
    case requireQuery
}
