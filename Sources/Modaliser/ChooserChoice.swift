import LispKit

/// A choice displayed in the chooser window.
/// Holds extracted display fields plus the original Scheme value for round-tripping
/// back to onSelect/action callbacks.
struct ChooserChoice {
    let text: String
    let subText: String?
    let icon: String?
    let iconType: String?
    let schemeValue: Expr
}
