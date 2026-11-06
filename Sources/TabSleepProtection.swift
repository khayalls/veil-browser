import Foundation

/// Shared by automatic unloading and the on-demand Performance controls.
struct TabSleepProtection:Equatable {
    var loading=false,playing=false,capture=false,upload=false,download=false,dirty=false,knownState=false
    var reason:String? {
        if loading{return "Loading"}
        if playing{return "Playing"}
        if capture{return "Camera, microphone or call"}
        if upload{return "Uploading"}
        if download{return "Downloading"}
        if !knownState{return "Checking page state"}
        if dirty{return "Unsaved changes"}
        return nil
    }
}

/// Pointer events within the same zone must not restart the sidebar dwell.
struct SidebarRevealIntent:Equatable {
    enum Zone:Equatable {case none,reveal,dismiss}
    private(set) var zone:Zone = .none
    mutating func transition(to next:Zone)->Bool{guard next != zone else{return false};zone=next;return true}
    mutating func reset(){zone = .none}
}
