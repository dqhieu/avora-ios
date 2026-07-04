import SwiftUI

extension Font {
    // Display tier — Cormorant Garamond
    static let avoraHero        = Font.custom("CormorantGaramond-SemiBold", size: 48, relativeTo: .largeTitle)
    static let avoraLargeTitle  = Font.custom("CormorantGaramond-SemiBold", size: 34, relativeTo: .largeTitle)
    static let avoraTitle       = Font.custom("CormorantGaramond-SemiBold", size: 28, relativeTo: .title)
    static let avoraTitle2      = Font.custom("CormorantGaramond-Medium",   size: 22, relativeTo: .title2)
    static let avoraTitle3      = Font.custom("CormorantGaramond-Medium",   size: 20, relativeTo: .title3)
    static let avoraSerifAccent = Font.custom("CormorantGaramond-MediumItalic", size: 20, relativeTo: .title3)

    // UI / body tier — Bricolage Grotesque
    static let avoraHeroSans = Font.custom("BricolageGrotesque-Regular", size: 48, relativeTo: .largeTitle)
    static let avoraHeadline    = Font.custom("BricolageGrotesque-SemiBold", size: 17, relativeTo: .headline)
    static let avoraBody        = Font.custom("BricolageGrotesque-Regular",  size: 17, relativeTo: .body)
    static let avoraCallout     = Font.custom("BricolageGrotesque-Regular",  size: 16, relativeTo: .callout)
    static let avoraSubheadline = Font.custom("BricolageGrotesque-Medium",   size: 15, relativeTo: .subheadline)
    static let avoraButton      = Font.custom("BricolageGrotesque-SemiBold", size: 17, relativeTo: .body)
    static let avoraFootnote    = Font.custom("BricolageGrotesque-Regular",  size: 13, relativeTo: .footnote)
    static let avoraCaption     = Font.custom("BricolageGrotesque-Medium",   size: 12, relativeTo: .caption)
    static let avoraCaption2    = Font.custom("BricolageGrotesque-Regular",  size: 11, relativeTo: .caption2)

    // Numeric display — Bricolage Grotesque (credit values, counts)
    static let avoraNumberLarge = Font.custom("BricolageGrotesque-SemiBold", size: 44, relativeTo: .largeTitle)
    static let avoraNumber      = Font.custom("BricolageGrotesque-SemiBold", size: 30, relativeTo: .title)
}

#if DEBUG
#Preview("Typography specimen") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reimagine your photos").font(.avoraHero)
            Text("Choose a style").font(.avoraLargeTitle)
            Text("Your collection").font(.avoraTitle)
            Text("Recent generations").font(.avoraTitle2)
            Text("Section header").font(.avoraTitle3)
            Text("“Crafted just for you.”").font(.avoraSerifAccent)
            Divider()
            Text("Vintage Film Portrait").font(.avoraHeadline)
            Text("Upload a photo and Avora transforms it in seconds.").font(.avoraBody)
            Text("Secondary body copy").font(.avoraCallout)
            Text("12 styles available").font(.avoraSubheadline)
            Text("Generate").font(.avoraButton)
            Text("Saved to your library").font(.avoraFootnote)
            Text("2 credits").font(.avoraCaption)
            Text("Updated just now").font(.avoraCaption2)
            Text("1,234 credits").font(.avoraTitle2.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
#endif
