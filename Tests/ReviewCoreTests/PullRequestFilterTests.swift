import Foundation
import ReviewCore
import Testing

@Suite
struct PullRequestFilterTests {
    private let harmony = RepositoryName(owner: "sodahealth", name: "harmony")

    @Test("The default filter searches open pull requests, most recently updated first")
    func defaults() {
        let query = PullRequestFilter().searchQuery(scope: ["repo:sodahealth/harmony"])
        #expect(query == "is:pr repo:sodahealth/harmony is:open sort:updated-desc")
    }

    @Test("Drafts by one author, and ready ones by anyone else")
    func draftsAndAuthors() {
        let mine = PullRequestFilter(readiness: .draft, people: [PersonCondition(role: .author, login: "kevin")])
        #expect(mine.searchQuery(scope: []) == "is:pr is:open draft:true author:kevin sort:updated-desc")

        let others = PullRequestFilter(
            readiness: .ready,
            people: [PersonCondition(role: .author, login: "@me", isExcluded: true)]
        )
        #expect(others.searchQuery(scope: []) == "is:pr is:open draft:false -author:@me sort:updated-desc")
    }

    @Test("Each role and review state has its qualifier")
    func qualifiers() {
        let filter = PullRequestFilter(
            state: .all,
            review: .changesRequested,
            people: [
                PersonCondition(role: .reviewedBy, login: "a"),
                PersonCondition(role: .reviewRequested, login: "sodahealth/backend"),
                PersonCondition(role: .assignee, login: "b", isExcluded: true),
                PersonCondition(role: .involves, login: "c"),
            ],
            sort: .oldest
        )
        #expect(
            filter.searchQuery(scope: [])
                == "is:pr review:changes_requested reviewed-by:a review-requested:sodahealth/backend -assignee:b involves:c sort:created-asc"
        )
    }

    @Test("Closed means closed without merging")
    func closedExcludesMerged() {
        #expect(PullRequestFilter(state: .closed).searchQuery(scope: []).contains("is:closed is:unmerged"))
        #expect(PullRequestFilter(state: .merged).searchQuery(scope: []).contains("is:merged"))
    }

    @Test("Words search titles, after every qualifier, and typed qualifiers pass through")
    func keywords() {
        let filter = PullRequestFilter(keywords: "  ledger label:bug ")
        #expect(filter.searchQuery(scope: []).hasSuffix("sort:updated-desc in:title ledger label:bug"))
    }

    @Test("A login that is not one yet is left out of the query")
    func invalidLoginsAreSkipped() {
        let filter = PullRequestFilter(people: [
            PersonCondition(role: .author, login: ""),
            PersonCondition(role: .author, login: "two words"),
            PersonCondition(role: .author, login: "x repo:other/repo"),
            PersonCondition(role: .author, login: "-dash"),
            PersonCondition(role: .reviewedBy, login: "@kevin"),
        ])
        #expect(filter.searchQuery(scope: []) == "is:pr is:open reviewed-by:kevin sort:updated-desc")
        #expect(filter.people[0].isBlank)
        #expect(!filter.people[1].isValid && !filter.people[1].isBlank)
    }

    @Test("@me is accepted in any case, and apps and teams keep their slash")
    func loginForms() {
        #expect(PersonCondition(role: .author, login: "@ME").qualifier == "author:@me")
        #expect(PersonCondition(role: .author, login: "app/dependabot").qualifier == "author:app/dependabot")
        #expect(PersonCondition(role: .author, login: "a/b/c").qualifier == nil)
    }

    @Test("Switching a token's sense changes its role and negation together")
    func sense() {
        var person = PersonCondition(role: .author, login: "dev")
        person.sense = PersonCondition.Sense(role: .reviewedBy, isExcluded: true)
        #expect(person.qualifier == "-reviewed-by:dev")
        #expect(PersonCondition.Sense.allCases.count == PersonCondition.Role.allCases.count * 2)
    }

    @Test("Conditions ignore the words and the sort")
    func hasConditions() {
        #expect(!PullRequestFilter(keywords: "x", sort: .newest).hasConditions)
        #expect(PullRequestFilter(readiness: .draft).hasConditions)
        #expect(PullRequestFilter(people: [PersonCondition(role: .author)]).hasConditions)
    }

    @Test("Scopes become repo qualifiers, and an empty tracked list searches what involves you")
    func scopes() {
        let other = RepositoryName(owner: "sodahealth", name: "nexus")
        #expect(BrowseScope.tracked.qualifiers(tracked: [harmony, other]) == ["repo:sodahealth/harmony", "repo:sodahealth/nexus"])
        #expect(BrowseScope.tracked.qualifiers(tracked: []) == ["involves:@me"])
        #expect(BrowseScope.involvingMe.qualifiers(tracked: [harmony]) == ["involves:@me"])
        #expect(BrowseScope.repository(other).qualifiers(tracked: [harmony]) == ["repo:sodahealth/nexus"])
    }

    @Test("A filter and its scope survive a round trip through JSON")
    func codable() throws {
        let filter = PullRequestFilter(
            keywords: "ledger", state: .merged, readiness: .ready, review: .approved,
            people: [PersonCondition(role: .reviewedBy, login: "@me", isExcluded: true)], sort: .newest
        )
        let decodedFilter = try JSONDecoder().decode(PullRequestFilter.self, from: JSONEncoder().encode(filter))
        #expect(decodedFilter == filter)
        let scope = BrowseScope.repository(harmony)
        #expect(try JSONDecoder().decode(BrowseScope.self, from: JSONEncoder().encode(scope)) == scope)
    }
}
