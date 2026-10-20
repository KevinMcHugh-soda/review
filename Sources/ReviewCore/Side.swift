/// Which version of a file a line belongs to.
///
/// `base` is the merge base — the old side of the diff, GitHub's `LEFT` —
/// and `head` is the PR's head commit, GitHub's `RIGHT`.
public enum Side: String, Hashable, Sendable, Codable {
    case base
    case head
}
