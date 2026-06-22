import Foundation
import CoreText

/// Registers any bundled `.ttf`/`.otf` files at launch, so no Info.plist
/// `UIAppFonts` entry is needed (this project generates its Info.plist).
///
/// To enable the design's typefaces, drop these files into the app target
/// (e.g. a `Design/Fonts` group, "Copy if needed" + target membership):
///   - LibreCaslonText-Regular.ttf  (serif headings)
///   - Inter-Regular.ttf            (sans body)
///   - JetBrainsMono-Regular.ttf    (mono metadata)
/// Until they're added, `Theme` falls back to the system fonts gracefully.
enum FontRegistrar {
    static func registerBundledFonts() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])

        guard !urls.isEmpty else {
            return
        }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }
}
