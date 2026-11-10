import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
enum WindowFrameSnapshot {
    struct Window {
        let id: CGWindowID
        let ownerPID: pid_t
        let title: String?
        let frame: CGRect

        init(id: CGWindowID, ownerPID: pid_t, title: String?, frame: CGRect) {
            self.id = id
            self.ownerPID = ownerPID
            self.title = title
            self.frame = frame
        }

        init?(info: [String: Any]) {
            guard
                let id = info[kCGWindowNumber as String] as? NSNumber,
                let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds),
                !frame.isEmpty, !frame.isNull
            else { return nil }

            self.init(
                id: id.uint32Value,
                ownerPID: owner.int32Value,
                title: info[kCGWindowName as String] as? String,
                frame: frame
            )
        }
    }

    struct Match: Equatable {
        let windowID: CGWindowID?
        let method: String

        static func resolve(
            windowID: CGWindowID?, ownerPID: pid_t, title: String?,
            frame: CGRect?, windows: [Window]?, applicationName: String? = nil
        ) -> Self {
            // An AX-provided ID remains authoritative even if the window is
            // temporarily absent from CGWindowList. Never switch to another ID.
            if let windowID, windowID != kCGNullWindowID {
                return Self(windowID: windowID, method: "AXWindowID")
            }
            guard let windows else { return Self(windowID: nil, method: "CGUnavailable") }
            let candidates = windows.filter { $0.ownerPID == ownerPID }
            var titles = Set([title].compactMap { $0 }.filter { !$0.isEmpty })
            if let title, let applicationName, title.hasSuffix(" - " + applicationName) {
                titles.insert(String(title.dropLast(applicationName.count + 3)))
            }
            let titled = candidates.filter { $0.title.map(titles.contains) ?? false }
            if titled.count == 1 { return Self(windowID: titled[0].id, method: "uniqueTitle") }
            if let frame {
                let matching = candidates.filter {
                    // Chrome's AX caption can append tab-group and memory
                    // details. A prefix alone never establishes identity.
                    if let cgTitle = $0.title, !titles.isEmpty, !cgTitle.isEmpty, !titles.contains(cgTitle) {
                        guard let title, let applicationName,
                              title.hasSuffix(" - " + applicationName),
                              title.hasPrefix(cgTitle + " - ")
                        else { return false }
                    }
                    return abs($0.frame.minX - frame.minX) <= 1 &&
                        abs($0.frame.minY - frame.minY) <= 1 &&
                        abs($0.frame.width - frame.width) <= 1 &&
                        abs($0.frame.height - frame.height) <= 1
                }
                if matching.count == 1 { return Self(windowID: matching[0].id, method: "uniquePreWriteFrame") }
            }
            return Self(windowID: nil, method: "unresolved")
        }
    }

    struct Binding {
        let ownerPID: pid_t
        let match: Match

        func frame() -> CGRect? {
            guard let id = match.windowID else { return nil }
            return (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?
                .compactMap { Window(info: $0) }
                .first { $0.id == id && $0.ownerPID == ownerPID }?.frame
        }
    }

    static func bind(
        window: AXUIElement, ownerPID: pid_t, applicationName: String?, frame: CGRect
    ) -> Binding {
        let windows = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]])?
            .compactMap { Window(info: $0) }
        return Binding(ownerPID: ownerPID, match: Match.resolve(
            windowID: AXAttributeReader.windowIdentifier(of: window), ownerPID: ownerPID,
            title: AXAttributeReader.string(kAXTitleAttribute as CFString, from: window),
            frame: frame, windows: windows, applicationName: applicationName
        ))
    }
}
