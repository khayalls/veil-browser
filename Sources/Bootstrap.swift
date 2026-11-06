import AppKit

var veilApplication: VeilAppDelegate?
@_cdecl("VEILSetupApplication")
func VEILSetupApplication() {
    let delegate = VeilAppDelegate()
    veilApplication = delegate
    NSApp.delegate = delegate
    NSApp.setActivationPolicy(.regular)
    delegate.start()
}
@_cdecl("VEILRequestQuit")
func VEILRequestQuit() { veilApplication?.quit() }
