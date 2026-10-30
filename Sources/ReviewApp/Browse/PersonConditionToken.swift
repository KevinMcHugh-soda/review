import ReviewCore
import SwiftUI

/// One person filter as a token: its role (a menu, to switch between "is"
/// and "is not" or to another role), the login, and a remove button. A login
/// that cannot be one is outlined in red and left out of the search.
struct PersonConditionToken: View {
    @Binding var person: PersonCondition
    var focus: FocusState<PersonCondition.ID?>.Binding
    let remove: () -> Void

    private var isFlagged: Bool { !person.isBlank && !person.isValid }

    var body: some View {
        HStack(spacing: Theme.tightSpacing) {
            Menu {
                Picker("Condition", selection: $person.sense) {
                    ForEach(PersonCondition.Sense.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(person.sense.title)
                    .font(Theme.Fonts.meta.weight(.semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            TextField("login or @me", text: $person.login)
                .textFieldStyle(.plain)
                .font(Theme.Fonts.meta)
                .frame(width: Theme.loginFieldWidth)
                .focused(focus, equals: person.id)

            Button("Remove Filter", systemImage: "xmark.circle.fill", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.badgePaddingHorizontal + 2)
        .padding(.vertical, Theme.badgePaddingVertical + 2)
        .background(.quaternary, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(.red, lineWidth: 1)
                .opacity(isFlagged ? 1 : 0)
        }
        .help(isFlagged ? "Not a GitHub login — left out of the search" : person.sense.title)
    }
}
