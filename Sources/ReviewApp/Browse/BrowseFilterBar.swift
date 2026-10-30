import ReviewCore
import SwiftUI

/// The filters above the browser's table: state, drafts and review as pop-up
/// menus, people as editable tokens added from Add Filter, and the sort.
/// People only take a second row once there are some.
struct BrowseFilterBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focusedPerson: PersonCondition.ID?

    var body: some View {
        @Bindable var browser = model.browser

        VStack(alignment: .leading, spacing: Theme.tightSpacing) {
            HStack(spacing: Theme.tightSpacing) {
                Picker("State", selection: $browser.filter.state) {
                    ForEach(PullRequestFilter.State.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Picker("Drafts", selection: $browser.filter.readiness) {
                    ForEach(PullRequestFilter.Readiness.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Picker("Review", selection: $browser.filter.review) {
                    ForEach(PullRequestFilter.Review.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
                addFilterMenu
                Spacer(minLength: Theme.spacing)
                if browser.filter.hasConditions {
                    Button("Clear") { browser.clearConditions() }
                        .help("Remove every filter but the search words")
                }
                Picker("Sort", selection: $browser.filter.sort) {
                    ForEach(PullRequestFilter.Sort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
                .help("Sort order")
            }
            .labelsHidden()

            if !browser.filter.people.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.tightSpacing) {
                        ForEach($browser.filter.people) { $person in
                            PersonConditionToken(person: $person, focus: $focusedPerson) {
                                browser.removePerson(person.id)
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.tightSpacing + 2)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var addFilterMenu: some View {
        Menu {
            Section {
                ForEach(PersonCondition.Role.allCases, id: \.self) { role in
                    Button("\(role.title(isExcluded: false))…") { add(role) }
                    if role == .author {
                        Button("\(role.title(isExcluded: true))…") { add(role, isExcluded: true) }
                    }
                }
            }
            Section("Quick Filters") {
                Button("Written by Me") { add(.author, login: "@me") }
                Button("Not Written by Me") { add(.author, isExcluded: true, login: "@me") }
                Button("Waiting on My Review") { add(.reviewRequested, login: "@me") }
                Button("Reviewed by Me") { add(.reviewedBy, login: "@me") }
            }
        } label: {
            Label("Add Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter by author, reviewer, assignee…")
    }

    /// A blank token takes the focus so the login can be typed at once.
    private func add(_ role: PersonCondition.Role, isExcluded: Bool = false, login: String = "") {
        let id = model.browser.addPerson(role, isExcluded: isExcluded, login: login)
        if login.isEmpty { focusedPerson = id }
    }
}
