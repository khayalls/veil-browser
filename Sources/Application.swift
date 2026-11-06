import AppKit

struct VeilCommand {
    let id:String,title:String,icon:String,key:String
    var modifiers:NSEvent.ModifierFlags = .command
}
final class VeilAppDelegate:NSObject,NSApplicationDelegate {
    var store:WorkspaceStore!
    var windows:[BrowserWindowController]=[]
    weak var lastActiveWindow:BrowserWindowController?
    var quitting=false
    private var qaBenchmark:QABenchmark?
    private var qaPerformance:QAPerformanceScenario?
    private var closingTabs=Set<UUID>()
    let commands:[VeilCommand]=[
        .init(id:"newTab",title:"New Tab",icon:"plus",key:"t"),
        .init(id:"location",title:"Change Address",icon:"magnifying-glass",key:"l"),
        .init(id:"newWindow",title:"New Window",icon:"squares-four",key:"n"),
        .init(id:"privateWindow",title:"New Private Window",icon:"shield-check",key:"n",modifiers:[.command,.shift]),
        .init(id:"closeTab",title:"Close Tab",icon:"x",key:"w"),
        .init(id:"closeWindow",title:"Close Window",icon:"x",key:"w",modifiers:[.command,.shift]),
        .init(id:"reopen",title:"Reopen Closed Tab",icon:"clock-counter-clockwise",key:"t",modifiers:[.command,.shift]),
        .init(id:"pin",title:"Pin or Unpin Tab",icon:"push-pin",key:"d"),
        .init(id:"favorite",title:"Add to Favorites",icon:"sparkle",key:""),
        .init(id:"sidebar",title:"Show or Hide Sidebar",icon:"sidebar-simple",key:"s"),
        .init(id:"savePage",title:"Save Page",icon:"download-simple",key:"s",modifiers:[.command,.option]),
        .init(id:"print",title:"Print",icon:"file",key:"p"),
        .init(id:"copyURL",title:"Copy Current URL",icon:"link",key:"c",modifiers:[.command,.shift]),
        .init(id:"copyMarkdown",title:"Copy URL as Markdown",icon:"link",key:"c",modifiers:[.command,.option,.shift]),
        .init(id:"recent",title:"Recent Tabs",icon:"clock-counter-clockwise",key:"\t",modifiers:.control),
        .init(id:"recentBack",title:"Previous Recent Tab",icon:"clock-counter-clockwise",key:"\t",modifiers:[.control,.shift]),
        .init(id:"previousSpace",title:"Previous Space",icon:"arrow-left",key:"\u{f702}",modifiers:[.command,.option]),
        .init(id:"nextSpace",title:"Next Space",icon:"arrow-right",key:"\u{f703}",modifiers:[.command,.option]),
        .init(id:"back",title:"Back",icon:"arrow-left",key:"["),
        .init(id:"forward",title:"Forward",icon:"arrow-right",key:"]"),
        .init(id:"reload",title:"Reload",icon:"arrow-clockwise",key:"r"),
        .init(id:"hardReload",title:"Reload Without Cache",icon:"arrow-clockwise",key:"r",modifiers:[.command,.shift]),
        .init(id:"find",title:"Find in Page",icon:"magnifying-glass",key:"f"),
        .init(id:"zoomIn",title:"Zoom In",icon:"plus",key:"+"),
        .init(id:"zoomOut",title:"Zoom Out",icon:"arrow-down",key:"-"),
        .init(id:"zoomReset",title:"Actual Size",icon:"squares-four",key:"0"),
        .init(id:"library",title:"Library and History",icon:"books",key:"y"),
        .init(id:"downloads",title:"Downloads",icon:"download-simple",key:"j",modifiers:[.command,.shift]),
        .init(id:"archive",title:"Archived Tabs",icon:"archive",key:""),
        .init(id:"clearTabs",title:"Archive Unpinned Tabs",icon:"archive",key:"k",modifiers:[.command,.shift]),
        .init(id:"onboarding",title:"Welcome Tour",icon:"ghost-duotone",key:""),
        .init(id:"performance",title:"Performance",icon:"battery-charging",key:""),
        .init(id:"newSpace",title:"New Space",icon:"planet",key:""),
        .init(id:"newFolder",title:"New Folder",icon:"folder-simple",key:""),
        .init(id:"settings",title:"Settings",icon:"sliders-horizontal",key:","),
        .init(id:"import",title:"Import Bookmarks or Workspace",icon:"arrow-down",key:""),
        .init(id:"export",title:"Export Workspace",icon:"arrow-square-out",key:""),
        .init(id:"devTools",title:"Developer Tools",icon:"command",key:"i",modifiers:[.command,.option])
    ]
    var active:BrowserWindowController?{windows.first(where:{$0.window === NSApp.mainWindow}) ?? lastActiveWindow ?? windows.last}
    func start(){
        let profile=URL(fileURLWithPath:VEProfileRoot())
        do{store=try WorkspaceRecovery.open(profile)}
        catch{
            let alert=NSAlert();alert.messageText="Your workspace needs a closer look.";alert.informativeText=error.localizedDescription+" Your original files are preserved."
            alert.addButton(withTitle:"Open Backup Copy");alert.addButton(withTitle:"Open Temporary Workspace");alert.addButton(withTitle:"Quit")
            switch alert.runModal(){
            case .alertFirstButtonReturn:
                do{store=try WorkspaceRecovery.openBackupCopy(profile)}catch{let failure=NSAlert();failure.messageText="That backup couldn't be opened.";failure.informativeText=error.localizedDescription+" Your original files are preserved.";failure.runModal();VEQuitEngine();return}
            case .alertSecondButtonReturn:
                do{store=try WorkspaceStore(directory:FileManager.default.temporaryDirectory.appendingPathComponent("VEIL-Recovery-"+UUID().uuidString))}catch{VEQuitEngine();return}
            default:VEQuitEngine();return
            }
        }
        buildMenus();newWindow()
        store.onError={[weak self] in self?.active?.showToast($0.localizedDescription)}
    }
    @discardableResult func newWindow(privateMode:Bool=false)->BrowserWindowController?{
        do{
            let workspace=privateMode ? try WorkspaceStore(directory:nil,privateMode:true):store!
            let controller=BrowserWindowController(store:workspace,coordinator:self)
            windows.append(controller);controller.showWindow(nil);controller.window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
            if let message=workspace.recoveryMessage{controller.showToast(message)}
            if windows.count==1 && !ProcessInfo.processInfo.arguments.contains("--veil-qa"){controller.showOnboarding()}
            if windows.count==1 && ProcessInfo.processInfo.arguments.contains("--veil-qa") && ProcessInfo.processInfo.arguments.contains("--veil-benchmark"){qaBenchmark=QABenchmark(browser:controller);DispatchQueue.main.asyncAfter(deadline:.now()+0.2){[weak self] in self?.qaBenchmark?.start()}}
            if windows.count==1 && ProcessInfo.processInfo.arguments.contains("--veil-qa") && ProcessInfo.processInfo.arguments.contains("--veil-performance-test"){qaPerformance=QAPerformanceScenario(browser:controller);DispatchQueue.main.asyncAfter(deadline:.now()+0.2){[weak self] in self?.qaPerformance?.start()}}
            return controller
        }catch{return nil}
    }
    func windowClosed(_ controller:BrowserWindowController){windows.removeAll{$0===controller};if quitting && windows.isEmpty{store.flush();VEQuitEngine()}}
    func quit(){guard !quitting else{return};quitting=true;store.flush();if windows.isEmpty{VEQuitEngine();return};for window in windows{window.requestCloseWindow()}}
    func cancelQuit(){quitting=false}
    func closeSharedTab(_ id:UUID,from source:BrowserWindowController,removePin:Bool){
        guard !closingTabs.contains(id) else{return};closingTabs.insert(id)
        let affected=windows.filter{$0.store === source.store},owners=affected.filter{$0.hasEngine(id)}
        let selected=Set(affected.filter{$0.selectedID==id}.map{ObjectIdentifier($0)})
        func next(_ index:Int){
            if index>=owners.count{
                source.store.closeTab(id,removePin:removePin)
                for controller in affected{controller.sharedTabClosed(id,wasSelected:selected.contains(ObjectIdentifier(controller)))}
                closingTabs.remove(id);source.sharedCloseFinished();return
            }
            owners[index].closeSharedEngine(id){[weak self] allowed in
                guard let self else{return}
                if allowed{next(index+1)}else{self.closingTabs.remove(id);for controller in affected{controller.sharedTabCloseCancelled()}}
            }
        }
        next(0)
    }
    func buildMenus(){
        let main=NSMenu()
        func section(_ title:String)->NSMenu{let item=NSMenuItem(title:title,action:nil,keyEquivalent:"");let sub=NSMenu(title:title);item.submenu=sub;main.addItem(item);return sub}
        func add(_ id:String,to menu:NSMenu){guard let cmd=commands.first(where:{$0.id==id}) else{return};let binding=store.state.settings.shortcuts[id].flatMap{ShortcutBinding($0)} ?? ShortcutBinding(key:cmd.key,flags:cmd.modifiers);let item=NSMenuItem(title:cmd.title,action:#selector(runCommand(_:)),keyEquivalent:binding.key);item.keyEquivalentModifierMask=binding.flags;item.target=self;item.representedObject=id;item.image=VeilIcon.image(cmd.icon)?.copy() as? NSImage;item.image?.size=NSSize(width:16,height:16);menu.addItem(item)}
        let app=section("VEIL");let about=NSMenuItem(title:"About VEIL",action:#selector(aboutVeil),keyEquivalent:"");about.target=self;app.addItem(about)
        add("settings",to:app);app.addItem(.separator());app.addItem(withTitle:"Hide VEIL",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h");app.addItem(.separator());app.addItem(withTitle:"Quit VEIL",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let file=section("File");["newTab","newWindow","privateWindow","reopen","closeTab","closeWindow","savePage","print","import","export"].forEach{add($0,to:file)}
        let edit=section("Edit");let undo=NSMenuItem(title:"Undo",action:#selector(undoChange),keyEquivalent:"z");undo.target=self;edit.addItem(undo)
        let redo=NSMenuItem(title:"Redo",action:#selector(redoChange),keyEquivalent:"z");redo.target=self;redo.keyEquivalentModifierMask=[.command,.shift];edit.addItem(redo)
        for (title,action,key) in [("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")]{edit.addItem(withTitle:title,action:Selector(action),keyEquivalent:key)}
        let view=section("View");["sidebar","location","reload","hardReload","find","zoomIn","zoomOut","zoomReset","performance","devTools"].forEach{add($0,to:view)}
        let full=NSMenuItem(title:"Enter Full Screen",action:#selector(NSWindow.toggleFullScreen(_:)),keyEquivalent:"f");full.keyEquivalentModifierMask=[.command,.control];view.addItem(full)
        let spaces=section("Spaces");["newSpace","newFolder","previousSpace","nextSpace"].forEach{add($0,to:spaces)}
        for n in 1...9{let item=NSMenuItem(title:"Select Space \(n)",action:#selector(selectSpaceNumber(_:)),keyEquivalent:String(n));item.keyEquivalentModifierMask=[.control,.option];item.target=self;item.tag=n;spaces.addItem(item)}
        let tabs=section("Tabs");["pin","favorite","recent","recentBack","copyURL","copyMarkdown"].forEach{add($0,to:tabs)}
        for n in 1...9{let item=NSMenuItem(title:"Select Tab \(n)",action:#selector(selectTabNumber(_:)),keyEquivalent:String(n));item.target=self;item.tag=n;tabs.addItem(item)}
        add("clearTabs",to:tabs)
        let library=section("Library");["library","downloads","archive"].forEach{add($0,to:library)}
        let window=section("Window");NSApp.windowsMenu=window;window.addItem(withTitle:"Minimize",action:#selector(NSWindow.performMiniaturize(_:)),keyEquivalent:"m")
        let help=section("Help");add("onboarding",to:help)
        NSApp.mainMenu=main
    }
    @objc private func runCommand(_ sender:NSMenuItem){if let id=sender.representedObject as? String{execute(id)}}
    @objc private func selectTabNumber(_ sender:NSMenuItem){active?.selectTabNumber(sender.tag)}
    @objc private func selectSpaceNumber(_ sender:NSMenuItem){if let active,active.store.state.spaces.indices.contains(sender.tag-1){active.selectSpace(active.store.state.spaces[sender.tag-1].id)}}
    @objc private func undoChange(){if let responder=NSApp.keyWindow?.firstResponder as? NSTextView{responder.undoManager?.undo()}else{active?.undoFocusedChange()}}
    @objc private func redoChange(){if let responder=NSApp.keyWindow?.firstResponder as? NSTextView{responder.undoManager?.redo()}else{active?.redoPageEditing()}}
    @objc private func aboutVeil(){NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"VEIL",.applicationVersion:"0.1.0",.credits:NSAttributedString(string:"A little more room.\nChromium + native macOS.\nIcons by Phosphor, MIT licensed.")])}
    func execute(_ id:String){
        if id=="closeTab",let key=NSApp.keyWindow,!windows.contains(where:{$0.window === key}){if key.styleMask.contains(.closable){key.performClose(nil)}else{key.cancelOperation(nil)};return}
        switch id{case "newWindow":newWindow();case "privateWindow":newWindow(privateMode:true);default:active?.execute(id)}
    }
    func applicationSupportsSecureRestorableState(_ app:NSApplication)->Bool{true}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{if !flag{newWindow()};return true}
    func application(_ application:NSApplication,open urls:[URL]){let target=active ?? newWindow();for url in urls where ["http","https"].contains(url.scheme ?? ""){target?.openURL(url.absoluteString)}}
}
final class ClosureMenuItem:NSMenuItem{
    let callback:()->Void
    init(title:String,action:@escaping()->Void){callback=action;super.init(title:title,action:#selector(invoke),keyEquivalent:"");target=self}
    required init(coder:NSCoder){fatalError()}
    @objc private func invoke(){callback()}
}
