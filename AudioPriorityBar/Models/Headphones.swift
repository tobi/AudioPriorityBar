import Foundation

/// Keywords used to detect headphone-like devices and auto-categorize them
struct HeadphoneDetection {
    /// Speaker product lines from brands that also make headphones.
    static let speakerKeywords: [String] = [
        "jabra speak",
    ]

    /// Device name keywords that indicate headphones/earbuds
    static let keywords: [String] = [
        // Generic terms
        "headphone",
        "headset",
        "earphone",
        "earbud",
        "earbuds",
        "buds",
        "ear",
        "pods",

        // Apple
        "airpods",
        "earpods",
        "beats",
        "powerbeats",
        "beatsx",
        "beats fit",
        "beats solo",
        "beats studio",

        // Sony
        "wh-1000",  // WH-1000XM series
        "wf-1000",  // WF-1000XM series
        "linkbuds",
        "inzone",

        // Samsung
        "galaxy buds",
        "buds pro",
        "buds live",
        "buds fe",

        // Bose
        "quietcomfort",
        "qc ultra",
        "qc45",
        "qc35",
        "soundsport",
        "sport earbuds",

        // Sennheiser
        "momentum",
        "hd 4",
        "hd 5",
        "pxc",

        // Jabra
        "jabra",
        "elite",
        "evolve",

        // JBL
        "jbl tune",
        "jbl live",
        "jbl tour",
        "jbl reflect",

        // Other brands
        "anker",
        "soundcore",
        "skullcandy",
        "nothing ear",
        "oneplus buds",
        "pixel buds",
        "huawei freebuds",
        "oppo enco",
        "technics eah",
        "bowers",
        "b&w px",
        "denon perl",
        "focal bathys",
        "hifiman",
        "shure aonic",
        "audio-technica ath",
        "beyerdynamic",
        "marshall",
        "bang & olufsen",
        "b&o",
        "akg",
        "plantronics",
        "poly",
        "razer",
        "steelseries",
        "hyperx",
        "logitech g pro",
        "astro",
        "corsair",
        "1more",
        "tozo",
        "edifier",
        "fiio",
        "moondrop",
    ]

    /// Check if a device name matches headphone patterns
    static func isHeadphone(deviceName: String) -> Bool {
        let nameLower = deviceName.lowercased()
        if speakerKeywords.contains(where: { nameLower.contains($0) }) {
            return false
        }
        return keywords.contains { nameLower.contains($0) }
    }
}
