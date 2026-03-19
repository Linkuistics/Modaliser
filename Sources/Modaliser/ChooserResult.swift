/// The outcome of a chooser interaction.
enum ChooserResult {
    /// User selected a choice (Return key or Cmd+digit).
    case selected(ChooserChoice, query: String)
    /// User triggered a named action (Cmd+Return for secondary, action panel, or digit shortcut).
    case action(actionIndex: Int, choice: ChooserChoice, query: String)
    /// User cancelled (Escape or focus loss).
    case cancelled
}
