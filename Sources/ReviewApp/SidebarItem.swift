import ReviewCore

/// What a sidebar row selects: the browser, or one pull request.
enum SidebarItem: Hashable {
    case browse
    case pullRequest(PullRequestReference)
}
