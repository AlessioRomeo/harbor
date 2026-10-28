import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker("Archive sessions left quiet for", selection: $model.autoArchiveDays) {
                ForEach(AppModel.autoArchiveChoices, id: \.self) { days in
                    Text(days == 0 ? "Never" : "\(days) days").tag(days)
                }
            }
            Text("Only sessions sitting at the prompt are archived. Their output is kept, and ⌘F still finds them.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
