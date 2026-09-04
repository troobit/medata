import SwiftUI

// The About / legal screen — design-handoff-00 §13, design-system/pages/
// about.md. Reached via a NavigationLink from Settings. Carries the food-source
// attributions that used to sit inline in Settings, a one-paragraph method
// summary, the not-a-medical-device statement, and the on-device privacy note.
// Legal and safety copy here is exempt from the minimal-wording rule (Req 13.1).
struct AboutView: View {
    var body: some View {
        List {
            Section("Data sources") {
                Text("CoFID — McCance & Widdowson, Food Standards Agency. Crown Copyright, Open Government Licence v3.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                Text("AFCD — Australian Food Composition Database, Food Standards Australia New Zealand, CC BY 4.0.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                Text("Nutrition5k — Google Research, CC BY 4.0. Values adapted: portion-volume calibration factors are derived from the dataset.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            Section("Method") {
                Text("Medata estimates carbohydrate content from one or two iPhone photos. On-device computer vision recovers each meal's three-dimensional shape — from LiDAR depth or two-view geometry — segments the foods, and multiplies the measured portion volume by density and composition values from the bundled CoFID and AFCD databases. Nothing is sent to a server.")
                    .font(.footnote)
                    .foregroundStyle(Color.textPrimary)
            }

            Section("Legal") {
                Text("Not a medical device")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Medata's estimates are informational and must not be relied upon for medical or dosing decisions.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                Text("All processing is on-device. Nothing leaves the phone.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
