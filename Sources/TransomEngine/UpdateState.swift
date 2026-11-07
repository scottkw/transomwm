/// What Settings ▸ Updates shows (gifsmith `UpdateStatus` states; 09-12 and 09-13 add the rest).
public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    /// Up to date; the running version.
    case current(String)
    case available(UpdateRelease)
}
