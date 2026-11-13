import Foundation
import ReviewCore
import Testing

@Suite
struct InboxItemTests {
    private func item(_ reasons: Set<InboxItem.Reason>) -> InboxItem {
        InboxItem(
            reference: PullRequestReference(owner: "acme", repository: "r", number: 1),
            title: "T", author: "dev", isDraft: false, updatedAt: .now, reasons: reasons
        )
    }

    @Test("Waits on the reviewer when asked by name or assigned, whatever the team setting")
    func waitsWhenAskedOrAssigned() {
        for includingTeam in [true, false] {
            #expect(item([.reviewRequested]).isWaitingOnReviewer(includingTeamRequests: includingTeam))
            #expect(item([.assigned]).isWaitingOnReviewer(includingTeamRequests: includingTeam))
            #expect(item([.teamReviewRequested, .reviewRequested]).isWaitingOnReviewer(includingTeamRequests: includingTeam))
        }
    }

    @Test("A team-only request waits on the reviewer only when team requests are included")
    func teamOnlyFollowsSetting() {
        #expect(item([.teamReviewRequested]).isWaitingOnReviewer(includingTeamRequests: true))
        #expect(!item([.teamReviewRequested]).isWaitingOnReviewer(includingTeamRequests: false))
    }

    @Test("The reviewer's own pull request never waits on them")
    func authoredNeverWaits() {
        for includingTeam in [true, false] {
            #expect(!item([.authored]).isWaitingOnReviewer(includingTeamRequests: includingTeam))
            #expect(!item([.authored, .assigned, .teamReviewRequested]).isWaitingOnReviewer(includingTeamRequests: includingTeam))
        }
    }
}
