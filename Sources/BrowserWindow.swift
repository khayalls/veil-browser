import AppKit
import QuartzCore

private struct TabRuntime{
    var loading=false,playing=false,dirty=true,capture=false,upload=false,crashed=false,knownState=false,hasMedia=false,mediaPrevious=false,mediaNext=false,muted=false,download=false
    var error:String?
    var title:String?
    var url:String?
    var mediaTitle="Media",mediaArtist=""
    var icon:NSImage?
    var iconOrigin:String?
    var sleepProtection:TabSleepProtection{TabSleepProtection(loading:loading,playing:playing,capture:capture,upload:upload,download:download,dirty:dirty,knownState:knownState)}
}
private enum CloseReason{case tab(removePin:Bool),shared,sleep,window}
final class BrowserWindowController:NSWindowController,NSWindowDelegate,VEEngineDelegate{
    let store:WorkspaceStore
    private var selection:WindowSelection
    var workspace:VeilWorkspace{
        let presentations=Dictionary(uniqueKeysWithValues:engines.keys.compactMap{id -> (UUID,WindowTabPresentation)? in guard let info=runtime[id] else{return nil};return (id,.init(title:info.title,url:info.url))})
        return selection.applying(to:store.state,presentations:presentations)
    }
    weak var coordinator:VeilAppDelegate?
    let root=WorkspaceRootView()
    private let content=NSView(),toolbar=NSView(),corners=ContentCornerMask(),resize=SidebarResizeHandle()
    private let sidebarMaterial=GlassSurface(radius:22,fallback:.sidebar),mediaCard=MediaCard(),swipeFeedback=SwipeFeedback()
    private var mediaID:UUID?,dismissedMediaID:UUID?
    private var downloadRecordIDs:[Int:UUID]=[:]
    private var downloadOwners:[UUID:(UUID,Int)]=[:]
    private var sidebar:SidebarView!
    private var home:EmptyPageView!
    private var errorPage:ErrorPageView!
    private var observer:UUID?
    private var engines:[UUID:VEEngineView]=[:]
    private var runtime=TabCache<TabRuntime>()
    private var closing:[UUID:CloseReason]=[:]
    private var sharedCloseCallbacks:[UUID:(Bool)->Void]=[:]
    private var tabRecords=TabCache<VeilTab>()
    private var bulkCloseQueue:[UUID]=[]
    private var displayedID:UUID?
    private var windowClosing=false
    private var sidebarPinned=true,sidebarReveal=false
    private var sidebarTransitioning=false,sidebarAnimationID=0
    private var webFullscreenTab:UUID?
    private var enteredFullscreenByPage=false,exitingFullscreen=false
    private var revealWork:DispatchWorkItem?
    private var revealIntent=SidebarRevealIntent()
    private var buttons:[String:ActionButton]=[:]
    private var address:AddressButton!
    private var palette:CommandPanel?
    private var editingAddress=false,recentMode=false
    private var recentMonitor:Any?
    private var fullscreenKeyMonitor:Any?
    private var auxiliary:NSWindowController?
    private var onboarding:OnboardingWindow?
    private var previewSpace:UUID?,previewChrome:VeilSpaceAppearance?
    private var optimizationTimer:Timer?
    private var memoryPressure:DispatchSourceMemoryPressure?
    private var toast=veilLabel("",size:12,weight:.medium,color:.secondaryLabelColor)
    private var toastWork:DispatchWorkItem?
    var selectedID:UUID?{selection.selectedTabID(in:store.state)}
    private var selectedTab:VeilTab?{selectedID.flatMap{id in workspace.tabs.first(where:{$0.id==id})}}
    private var currentEngine:VEEngineView?{selectedID.flatMap{engines[$0]}}
    private var selectedURL:String?{if let url=currentEngine?.currentURL,Navigation.isSupportedURL(url){return url};return selectedTab?.url}
    private func rememberEngineURL(_ id:UUID){if let url=engines[id]?.currentURL,Navigation.isSupportedURL(url){store.updateMetadata(tabID:id,url:url)}}
    init(store:WorkspaceStore,coordinator:VeilAppDelegate){
        self.store=store;self.coordinator=coordinator;selection=WindowSelection(store.state)
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:820),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="VEIL";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.minSize=NSSize(width:900,height:600);window.isReleasedWhenClosed=false
        window.isOpaque=false;window.backgroundColor = .clear
        super.init(window:window);window.delegate=self;window.contentView=root;window.center();window.setFrameAutosaveName(store.isPrivate ? "VEIL.Private":"VEIL.Main")
        if ProcessInfo.processInfo.arguments.contains("--veil-qa"),let flag=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--veil-qa-size=")}){let values=flag.dropFirst(15).split(separator:"x").compactMap{Double($0)};if values.count==2{window.setContentSize(NSSize(width:max(900,values[0]),height:max(600,values[1])))}}
        root.onLayout={ [weak self] in self?.layout() };root.onPointer={ [weak self] in self?.pointerMoved($0) }
        sidebar=SidebarView(owner:self);home=EmptyPageView{ [weak self] in self?.showCommandBar() }
        errorPage=ErrorPageView{[weak self] in self?.execute("reload")};errorPage.isHidden=true
        sidebarMaterial.content.addSubview(sidebar)
        [content,home,errorPage,corners,swipeFeedback,toolbar,sidebarMaterial,resize,mediaCard,toast].forEach{root.addSubview($0)};toast.isHidden=true;toast.alignment = .center;swipeFeedback.isHidden=true
        mediaCard.onAction={ [weak self] in self?.mediaAction($0) }
        for (id,icon,help) in [("back","arrow-left","Back"),("forward","arrow-right","Forward"),("reload","arrow-clockwise","Reload"),("sidebar","sidebar-simple","Show or hide sidebar"),("pin","push-pin","Pin or unpin tab"),("settings","sliders-horizontal","Settings")]{
            let button=ActionButton(icon:icon,help:help){ [weak self] in self?.execute(id) };buttons[id]=button;toolbar.addSubview(button);button.setAccessibilityIdentifier("veil.toolbar.\(id)")
        }
        address=AddressButton{ [weak self] in self?.showCommandBar(editing:true) };toolbar.addSubview(address);address.setAccessibilityIdentifier("veil.address")
        resize.onResize={ [weak self] width in guard let self else{return};let value=min(360,max(220,width));self.store.change(undoable:false){$0.settings.sidebarWidth=value} }
        observer=store.observe{ [weak self] in self?.stateChanged() };if store.isPrivate{store.onError={ [weak self] in self?.showToast($0.localizedDescription) }}
        optimizationTimer=Timer.scheduledTimer(withTimeInterval:30,repeats:true){ [weak self] _ in self?.optimizeTabs() }
        optimizationTimer?.tolerance=5
        memoryPressure=DispatchSource.makeMemoryPressureSource(eventMask:[.warning,.critical],queue:.main);memoryPressure?.setEventHandler{[weak self] in self?.optimizeTabs(pressure:true)};memoryPressure?.resume()
        fullscreenKeyMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in guard let self,event.window === self.window,self.webFullscreenTab != nil else{return event};if event.keyCode==53{self.leaveWebFullscreen();return nil};return event}
        stateChanged()
        if !store.isPrivate,let argument=ProcessInfo.processInfo.arguments.first(where:{$0.hasPrefix("--veil-url=")}),let url=Navigation.resolve(String(argument.dropFirst(11))){openURL(url)}
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{optimizationTimer?.invalidate();memoryPressure?.cancel();if let observer{store.removeObserver(observer)};if let recentMonitor{NSEvent.removeMonitor(recentMonitor)};if let fullscreenKeyMonitor{NSEvent.removeMonitor(fullscreenKeyMonitor)}}
    private func stateChanged(){
        guard !windowClosing else{return};selection.reconcile(store.state);let settings=store.state.settings
        let ids=Set(store.state.tabs.map(\.id));for (id,engine) in engines where !ids.contains(id) && closing[id]==nil{closing[id] = .sleep;engine.closeBrowser(false)}
        for tab in store.state.tabs{tabRecords[tab.id]=tab}
        pruneTabCaches()
        window?.appearance=settings.appearance=="dark" ? NSAppearance(named:.darkAqua):(settings.appearance=="light" ? NSAppearance(named:.aqua):nil)
        applyChromeAppearance();sidebar.render();layout();showSelected();refreshToolbar()
    }
    func previewAppearance(_ value:VeilSpaceAppearance?,space:UUID){previewSpace=value==nil ? nil:space;previewChrome=value;applyChromeAppearance()}
    private func applyChromeAppearance(){let space=workspace.space,theme=previewSpace==space.id ? previewChrome:space.appearance;root.tint=theme?.accentHex.flatMap(VeilPalette.color) ?? VeilPalette.accent(space.color);root.background=theme?.backgroundHex.flatMap(VeilPalette.color) ?? .windowBackgroundColor;root.gradient=theme?.style != "solid";root.chromeOpacity=store.state.settings.material ? CGFloat(theme?.opacity ?? 0.92):1;sidebarMaterial.tint=root.tint.withAlphaComponent(0.06);if let background=theme?.backgroundHex.flatMap(VeilPalette.color){let brightness=background.redComponent*0.2126+background.greenComponent*0.7152+background.blueComponent*0.0722;root.appearance=NSAppearance(named:brightness<0.5 ? .darkAqua:.aqua)}else{root.appearance=nil}}
    private func layout(){
        let fullscreen=webFullscreenTab != nil
        let width=root.bounds.width,height=root.bounds.height,sidebarWidth=CGFloat(store.state.settings.sidebarWidth),contentX=fullscreen ? 0:(sidebarPinned ? CGFloat(store.state.settings.sidebarWidth):8)
        content.frame=NSRect(x:contentX,y:fullscreen ? 0:48,width:max(200,width-contentX-(fullscreen ? 0:8)),height:max(100,height-(fullscreen ? 0:56)));for engine in engines.values{engine.frame=content.bounds}
        toolbar.isHidden=fullscreen
        home.frame=content.frame;corners.frame=content.frame;corners.color=NSColor.windowBackgroundColor.blended(withFraction:0.07,of:root.tint) ?? .windowBackgroundColor
        errorPage.frame=content.frame
        toolbar.frame=NSRect(x:0,y:7,width:width,height:34);buttons["sidebar"]?.frame=NSRect(x:98,y:0,width:30,height:30)
        let navX=sidebarPinned ? sidebarWidth+5:140
        buttons["back"]?.frame=NSRect(x:navX,y:0,width:29,height:30);buttons["forward"]?.frame=NSRect(x:navX+32,y:0,width:29,height:30);buttons["reload"]?.frame=NSRect(x:navX+64,y:0,width:29,height:30)
        buttons["settings"]?.frame=NSRect(x:width-42,y:0,width:30,height:30);buttons["pin"]?.frame=NSRect(x:width-77,y:0,width:30,height:30)
        let available=max(130,width-navX-200),addressWidth=min(420,available);address.frame=NSRect(x:navX+100+(available-addressWidth)/2,y:0,width:addressWidth,height:30)
        if !sidebarTransitioning{sidebarMaterial.frame=NSRect(x:sidebarPinned ? 6:12,y:sidebarPinned ? 48:58,width:sidebarWidth-(sidebarPinned ? 12:16),height:height-(sidebarPinned ? 54:74))}
        sidebar.frame=NSRect(origin:.zero,size:sidebarMaterial.frame.size)
        sidebarMaterial.isHidden = fullscreen || (!sidebarPinned && !sidebarReveal && !sidebarTransitioning);sidebarMaterial.enabled=store.state.settings.material
        resize.frame=NSRect(x:sidebarWidth-4,y:48,width:7,height:height-52);resize.isHidden = fullscreen || !sidebarPinned
        toast.frame=NSRect(x:contentX+30,y:height-44,width:max(200,width-contentX-60),height:26)
        mediaCard.frame=NSRect(x:width-286,y:height-118,width:270,height:100)
        swipeFeedback.frame=content.frame
    }
    private func showSelected(){
        let id=selectedID;if displayedID != id{for engine in engines.values{engine.isHidden=true};displayedID=id}
        guard let id,let tab=selectedTab else{home.isHidden=false;errorPage.isHidden=true;corners.isHidden=true;return}
        home.isHidden=true;corners.isHidden=webFullscreenTab != nil
        let errorWasVisible = !errorPage.isHidden
        let newlyVisibleError=errorPage.isHidden && runtime[id]?.error != nil;errorPage.isHidden=runtime[id]?.error==nil
        if let error=runtime[id]?.error{engines[id]?.isHidden=true;errorPage.title.stringValue=runtime[id]?.crashed == true ? "That tab needs a fresh start.":"Couldn't load this page.";errorPage.detail.stringValue=error;if newlyVisibleError{errorPage.focusRetry()};return}
        if let engine=engines[id]{let revealed=engine.isHidden;engine.isHidden=false;if revealed || errorWasVisible{DispatchQueue.main.async{[weak self,weak engine] in guard let self,let engine,self.selectedID==id,self.closing[id]==nil,self.window?.isKeyWindow==true,self.palette?.isVisible != true else{return};engine.focusPage();NSAccessibility.post(element:engine,notification:.layoutChanged)}};return};guard closing[id]==nil else{return}
        let engine=VEEngineView(frame:content.bounds,privateMode:store.isPrivate);engine.delegate=self;engine.autoresizingMask=[.width,.height]
        engines[id]=engine;var info=runtime[id] ?? TabRuntime();info.loading=true;info.title=tab.title;info.url=tab.url;runtime[id]=info;content.addSubview(engine);engine.start(withURL:tab.url)
    }
    func favicon(for id:UUID)->NSImage?{
        guard let tab=store.state.tabs.first(where:{$0.id==id}) else{return nil}
        let url=(engines[id] != nil ? runtime[id]?.url:nil) ?? tab.url,origin=FaviconStore.origin(url)
        if let info=runtime[id],info.iconOrigin==origin,let icon=info.icon{return icon}
        guard let data=store.favicons.data(for:url),let image=NSImage(data:data) else{return nil};image.isTemplate=false
        var info=runtime[id] ?? TabRuntime();info.icon=image;info.iconOrigin=origin;runtime[id]=info;return image
    }
    func title(for id:UUID)->String{guard let tab=store.state.tabs.first(where:{$0.id==id}) else{return "Tab"};return tab.customTitle ?? (engines[id] != nil ? runtime[id]?.title:nil) ?? tab.title}
    private func pruneTabCaches(){let retained=Set(store.state.tabs.map(\.id)).union(engines.keys).union(closing.keys).union(sharedCloseCallbacks.keys);runtime.retain(retained);tabRecords.retain(retained)}
    func isSleeping(_ id:UUID)->Bool{engines[id]==nil}
    func isPlaying(_ id:UUID)->Bool{runtime[id]?.playing == true}
    func prepareMutation(){if store.state.activeSpace != selection.activeSpace{store.selectSpace(selection.activeSpace)}}
    func selectSpace(_ id:UUID){if id != workspace.activeSpace{leaveWebFullscreen()};selection.selectSpace(id,in:store.state);store.selectSpace(id);stateChanged()}
    @discardableResult func openURL(_ url:String)->UUID{leaveWebFullscreen();prepareMutation();let id=store.addTab(url:url);if let tab=store.state.tabs.first(where:{$0.id==id}){selection.selectTab(tab)};stateChanged();return id}
    func selectTab(_ id:UUID){guard !windowClosing,let tab=store.state.tabs.first(where:{$0.id==id}) else{return};if id != selectedID{leaveWebFullscreen()};selection.selectTab(tab);prepareMutation();store.selectTab(id);stateChanged();currentEngine?.focusPage()}
    func selectTabNumber(_ number:Int){let tabs=workspace.visibleTabs();guard !tabs.isEmpty else{return};let index=number==9 ? tabs.count-1:number-1;if tabs.indices.contains(index){selectTab(tabs[index].id)}}
    func undoFocusedChange(){if let responder=window?.firstResponder as? NSView,responder.isDescendant(of:content){currentEngine?.undoEditing()}else if NSApp.keyWindow === window{store.undo()}}
    func redoPageEditing(){if let responder=window?.firstResponder as? NSView,responder.isDescendant(of:content){currentEngine?.redoEditing()}}
    func closeTab(_ id:UUID,removePin:Bool=false){
        guard closing[id]==nil else{return}
        if store.state.tabs.first(where:{$0.id==id})?.pinned==true && !removePin{let selected=selectedID==id;closeSharedEngine(id){[weak self] allowed in guard let self else{return};if allowed{self.sharedTabClosed(id,wasSelected:selected);self.sharedCloseFinished()}else{self.sharedTabCloseCancelled()}}}
        else{coordinator?.closeSharedTab(id,from:self,removePin:removePin)}
    }
    func hasEngine(_ id:UUID)->Bool{engines[id] != nil}
    func closeSharedEngine(_ id:UUID,completion:@escaping(Bool)->Void){guard let engine=engines[id] else{completion(true);return};guard closing[id]==nil else{completion(false);return};sharedCloseCallbacks[id]=completion;closing[id] = .shared;engine.closeBrowser(false)}
    func sharedTabClosed(_ id:UUID,wasSelected:Bool){if wasSelected{let others=workspace.visibleTabs().filter{$0.id != id}.sorted{$0.lastUsed>$1.lastUsed};if let next=others.first{selectTab(next.id)}else{selection.clear()}};stateChanged()}
    func sharedTabCloseCancelled(){bulkCloseQueue=[];stateChanged()}
    func sharedCloseFinished(){DispatchQueue.main.async{[weak self] in self?.closeNextBulkTab()}}
    private func finishCloseTab(_ id:UUID,removePin:Bool){
        let wasSelected=selectedID==id,others=workspace.visibleTabs().filter{$0.id != id}.sorted{$0.lastUsed>$1.lastUsed}
        store.closeTab(id,removePin:removePin)
        if wasSelected{if let next=others.first{selectTab(next.id)}else{selection.clear();store.change(undoable:false){s in for i in s.spaces.indices where s.spaces[i].lastTab==id{s.spaces[i].lastTab=nil}}}}
        sidebar.render();showSelected()
    }
    func requestCloseWindow(){guard !windowClosing else{return};windowClosing=true;palette?.dismiss();auxiliary?.close();onboarding?.close();store.flush();if engines.isEmpty{finishCloseWindow();return};closeNextWindowEngine()}
    private func closeNextWindowEngine(){guard windowClosing else{return};if let (id,engine)=engines.first{closing[id] = .window;engine.closeBrowser(false)}else{finishCloseWindow()}}
    private func closeNextBulkTab(){guard !bulkCloseQueue.isEmpty,!windowClosing else{return};let id=bulkCloseQueue.removeFirst();closeTab(id)}
    private func finishCloseWindow(){window?.orderOut(nil);window?.close();coordinator?.windowClosed(self)}
    func windowShouldClose(_ sender:NSWindow)->Bool{if windowClosing && engines.isEmpty{return true};requestCloseWindow();return false}
    func windowDidBecomeMain(_ notification:Notification){coordinator?.lastActiveWindow=self}
    func windowWillExitFullScreen(_ notification:Notification){exitingFullscreen=true;if let id=webFullscreenTab{engines[id]?.executeScript("if(document.fullscreenElement)document.exitFullscreen().catch(()=>{})")}}
    func windowDidExitFullScreen(_ notification:Notification){exitingFullscreen=false;enteredFullscreenByPage=false;webFullscreenTab=nil;layout();showSelected();refreshMedia()}
    private func setWebFullscreen(_ value:Bool,tab:UUID){
        if value{guard tab==selectedID else{engines[tab]?.executeScript("if(document.fullscreenElement)document.exitFullscreen().catch(()=>{})");return};webFullscreenTab=tab;enteredFullscreenByPage=window?.styleMask.contains(.fullScreen) != true;if enteredFullscreenByPage{window?.toggleFullScreen(nil)}}
        else if webFullscreenTab==tab{webFullscreenTab=nil;if enteredFullscreenByPage,!exitingFullscreen,window?.styleMask.contains(.fullScreen)==true{window?.toggleFullScreen(nil)};enteredFullscreenByPage=false}
        layout();showSelected();refreshMedia()
    }
    private func leaveWebFullscreen(){if let id=webFullscreenTab{engines[id]?.executeScript("if(document.fullscreenElement)document.exitFullscreen().catch(()=>{})");setWebFullscreen(false,tab:id)}}
    func showCommandBar(editing:Bool=false){
        leaveWebFullscreen()
        prepareMutation()
        palette?.dismiss();editingAddress=editing;recentMode=false
        palette=CommandPanel(owner:window!,provider:{ [weak self] in self?.commandResults($0) ?? [] },onDismiss:{})
        palette?.openInNewTab={ [weak self] query in guard let self,let url=Navigation.resolve(query,searchEngine:self.store.state.settings.searchEngine) else{return};self.openURL(url) }
        palette?.show(initial:editing ? selectedURL ?? "":"")
    }
    private func commandResults(_ query:String)->[CommandResult]{
        let q=query.trimmingCharacters(in:.whitespacesAndNewlines),state=workspace;var result:[CommandResult]=[]
        let matches=state.tabs.filter{q.isEmpty || $0.displayTitle.localizedStandardContains(q) || $0.url.localizedStandardContains(q)}.sorted{$0.lastUsed>$1.lastUsed}
        for tab in matches.prefix(q.isEmpty ? 5:7){result.append(.init(title:tab.displayTitle,subtitle:Navigation.displayHost(tab.url),icon:"globe",badge:"Switch to tab",action:{ [weak self] in self?.selectTab(tab.id) },image:favicon(for:tab.id)))}
        if !q.isEmpty{
            if let url=Navigation.resolve(q,searchEngine:state.settings.searchEngine){
                let isURL = !url.contains("duckduckgo.com/?q=") && !url.contains("google.com/search?q=")
                let navigation=CommandResult(title:isURL ? "Go to \(Navigation.displayHost(url))":"Search for “\(q)”",subtitle:isURL ? url:state.settings.searchEngine,icon:isURL ? "arrow-square-out":"magnifying-glass",badge:editingAddress ? "Current tab":"New tab",action:{ [weak self] in guard let self else{return};if self.editingAddress,let id=self.selectedID{self.store.updateMetadata(tabID:id,url:url);self.engines[id]?.loadURL(url)}else{self.openURL(url)} })
                if editingAddress || (isURL && !matches.contains(where:{Navigation.canonicalURL($0.url)==Navigation.canonicalURL(url)})){result.insert(navigation,at:0)}else{result.append(navigation)}
            }else{result.insert(.init(title:"Use an http or https address",subtitle:"That address cannot be opened here.",icon:"warning-circle",badge:"",action:nil),at:0)}
        }
        for command in coordinator?.commands ?? [] where command.id != "recentBack" && (q.isEmpty ? ["newSpace","library","settings"].contains(command.id):command.title.localizedStandardContains(q)){
            let item=CommandResult(title:command.title,subtitle:"VEIL command",icon:command.icon,badge:command.key.isEmpty ? "Run command":"Shortcut",action:{ [weak self] in self?.coordinator?.execute(command.id) })
            if !q.isEmpty,command.title.lowercased().hasPrefix(q.lowercased()){result.insert(item,at:0)}else{result.append(item)}
        }
        if !q.isEmpty{for space in state.spaces where space.name.localizedStandardContains(q){let item=CommandResult(title:space.name,subtitle:"VEIL Space",icon:space.icon,badge:"Switch Space",action:{[weak self] in self?.selectSpace(space.id)});if space.name.lowercased().hasPrefix(q.lowercased()){result.insert(item,at:0)}else{result.append(item)}}}
        if !q.isEmpty && !store.isPrivate{let openURLs=Set(state.tabs.map(\.url));for visit in state.history.filter({!openURLs.contains($0.url) && ($0.title.localizedStandardContains(q) || $0.url.localizedStandardContains(q))}).prefix(4){result.append(.init(title:visit.title,subtitle:Navigation.displayHost(visit.url),icon:"clock-counter-clockwise",badge:"History",action:{ [weak self] in self?.openURL(visit.url) }))}}
        return Array(result.prefix(14))
    }
    func execute(_ id:String){
        prepareMutation()
        switch id{
        case "newTab":showCommandBar()
        case "location":showCommandBar(editing:true)
        case "closeTab":if let selectedID{closeTab(selectedID)}
        case "closeWindow":requestCloseWindow()
        case "reopen":if let id=store.reopenLast(){selectTab(id)}
        case "pin":if let selectedID{rememberEngineURL(selectedID);store.togglePin(selectedID)}
        case "favorite":if let selectedID{rememberEngineURL(selectedID);store.moveTab(selectedID,to:workspace.activeSpace,pin:true,favorite:true)}
        case "sidebar":revealWork?.cancel();revealWork=nil;revealIntent.reset();sidebarAnimationID+=1;sidebarTransitioning=false;sidebarPinned.toggle();sidebarReveal=false;sidebarMaterial.alphaValue=1;layout()
        case "back":currentEngine?.goBack()
        case "forward":currentEngine?.goForward()
        case "reload","hardReload":if let selectedID{runtime[selectedID]?.error=nil;showSelected()};currentEngine?.reloadIgnoringCache(id=="hardReload");currentEngine?.focusPage()
        case "copyURL":copyCurrentURL(markdown:false)
        case "copyMarkdown":copyCurrentURL(markdown:true)
        case "zoomIn":currentEngine?.setPageZoom(min(5,(currentEngine?.pageZoom ?? 0)+0.5))
        case "zoomOut":currentEngine?.setPageZoom(max(-5,(currentEngine?.pageZoom ?? 0)-0.5))
        case "zoomReset":currentEngine?.setPageZoom(0)
        case "find":if let text=textPrompt(title:"Find in page",button:"Find"){currentEngine?.findText(text,forward:true)}
        case "library":showLibrary()
        case "downloads":showLibrary(section:"Downloads")
        case "archive":showLibrary(section:"Archived")
        case "onboarding":showOnboarding(replay:true)
        case "clearTabs":bulkCloseQueue=store.state.tabs.filter{$0.spaceID==workspace.activeSpace && !$0.pinned}.map(\.id);closeNextBulkTab()
        case "settings":showSettings()
        case "newSpace":newSpace()
        case "newFolder":newFolder()
        case "previousSpace":cycleSpace(-1)
        case "nextSpace":cycleSpace(1)
        case "recent":cycleRecent(1)
        case "recentBack":cycleRecent(-1)
        case "performance":showPerformance()
        case "devTools":currentEngine?.showDevTools()
        case "export":exportWorkspace()
        case "import":importWorkspace()
        case "savePage":saveHTMLPage()
        case "print":currentEngine?.executeScript("window.print()")
        default:break
        }
    }
    private func cycleSpace(_ direction:Int){let spaces=store.state.spaces,index=store.state.spaces.firstIndex(where:{$0.id==workspace.activeSpace}) ?? 0;selectSpace(spaces[(index+direction+spaces.count)%spaces.count].id)}
    private func cycleRecent(_ direction:Int){
        if recentMode,palette?.isVisible==true{palette?.advance(direction);return}
        let tabs=store.state.tabs.sorted{$0.lastUsed>$1.lastUsed};palette?.dismiss();recentMode=true
        palette=CommandPanel(owner:window!,provider:{ [weak self] query in tabs.filter{query.isEmpty || $0.title.localizedStandardContains(query)}.map{tab in CommandResult(title:tab.displayTitle,subtitle:Navigation.displayHost(tab.url),icon:"globe",badge:"Recent tab",action:{ [weak self] in self?.selectTab(tab.id) })} },onDismiss:{ [weak self] in self?.recentMode=false })
        palette?.show();palette?.advance(direction)
        if let recentMonitor{NSEvent.removeMonitor(recentMonitor)}
        recentMonitor=NSEvent.addLocalMonitorForEvents(matching:.flagsChanged){ [weak self] event in if !event.modifierFlags.contains(.control),self?.recentMode==true{self?.palette?.commit();if let monitor=self?.recentMonitor{NSEvent.removeMonitor(monitor);self?.recentMonitor=nil}};return event }
    }
    private func copyCurrentURL(markdown:Bool){guard let tab=selectedTab else{return};let title=tab.title.replacingOccurrences(of:"]",with:"\\]");let url=selectedURL ?? tab.url;let value=markdown ? "[\(title)](\(url))":url;NSPasteboard.general.clearContents();NSPasteboard.general.setString(value,forType:.string);showToast("Link copied.")}
    private func refreshToolbar(){address.setAddress(selectedURL.map{Navigation.displayHost($0)} ?? (store.isPrivate ? "Private browsing":"VEIL"));buttons["back"]?.isEnabled=currentEngine?.canGoBack ?? false;buttons["forward"]?.isEnabled=currentEngine?.canGoForward ?? false;buttons["pin"]?.selectedState=selectedTab?.pinned ?? false;window?.title=selectedID.map{title(for:$0)+" — VEIL"} ?? "VEIL"}
    private func pointerMoved(_ event:NSEvent){
        guard !windowClosing,!sidebarPinned,webFullscreenTab==nil else{return};let point=root.convert(event.locationInWindow,from:nil)
        let zone:SidebarRevealIntent.Zone
        if !sidebarReveal,event.type != .mouseExited,point.x<=8,point.y>45{zone = .reveal}
        else if sidebarReveal && (point.x>CGFloat(store.state.settings.sidebarWidth)+14 || event.type == .mouseExited){zone = .dismiss}
        else{zone = .none}
        guard revealIntent.transition(to:zone) else{return}
        revealWork?.cancel();revealWork=nil
        guard zone != .none else{return}
        let item=DispatchWorkItem{[weak self] in guard let self,!self.windowClosing,self.revealIntent.zone==zone else{return};self.revealWork=nil;self.setSidebarRevealed(zone == .reveal)}
        revealWork=item;DispatchQueue.main.asyncAfter(deadline:.now()+(zone == .reveal ? 0.24:0.28),execute:item)
    }
    private func setSidebarRevealed(_ visible:Bool){
        guard !sidebarPinned,sidebarReveal != visible else{return};sidebarAnimationID+=1;let generation=sidebarAnimationID
        sidebarTransitioning=false;sidebarReveal=visible
        if store.state.settings.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion{sidebarMaterial.alphaValue=1;layout();return}
        if visible{layout();let target=sidebarMaterial.frame;sidebarMaterial.frame=target.offsetBy(dx:-12,dy:0);sidebarMaterial.alphaValue=0;sidebarTransitioning=true
            NSAnimationContext.runAnimationGroup({context in context.duration=0.22;context.timingFunction=CAMediaTimingFunction(controlPoints:0.22,1,0.36,1);self.sidebarMaterial.animator().setFrameOrigin(target.origin);self.sidebarMaterial.animator().alphaValue=1},completionHandler:{[weak self] in guard let self,self.sidebarAnimationID==generation else{return};self.sidebarTransitioning=false;self.layout()})
        }else{sidebarTransitioning=true;let origin=sidebarMaterial.frame.origin
            NSAnimationContext.runAnimationGroup({context in context.duration=0.16;context.timingFunction=CAMediaTimingFunction(name:.easeIn);self.sidebarMaterial.animator().setFrameOrigin(NSPoint(x:origin.x-8,y:origin.y));self.sidebarMaterial.animator().alphaValue=0},completionHandler:{[weak self] in guard let self,self.sidebarAnimationID==generation else{return};self.sidebarTransitioning=false;self.layout();self.sidebarMaterial.alphaValue=1})
        }
    }
    func showToast(_ message:String){toastWork?.cancel();toast.stringValue=message;toast.isHidden=false;let item=DispatchWorkItem{ [weak self] in self?.toast.isHidden=true };toastWork=item;DispatchQueue.main.asyncAfter(deadline:.now()+2.5,execute:item)}
    func setFolder(_ id:UUID,collapsed:Bool){store.change{s in if let i=s.folders.firstIndex(where:{$0.id==id}){s.folders[i].collapsed=collapsed}}}
    private func textPrompt(title:String,value:String="",button:String="Save")->String?{let alert=NSAlert();alert.messageText=title;let field=NSTextField(string:value);field.frame=NSRect(x:0,y:0,width:280,height:26);alert.accessoryView=field;alert.addButton(withTitle:button);alert.addButton(withTitle:"Cancel");alert.window.initialFirstResponder=field;guard alert.runModal() == .alertFirstButtonReturn else{return nil};let text=field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);return text.isEmpty ? nil:text}
    private func newSpace(){if let name=textPrompt(title:"Make some space.",button:"Create Space"){let id=store.addSpace(name:name,color:store.state.spaces.count);selectSpace(id)}}
    private func newFolder(){if let name=textPrompt(title:"New folder",button:"Create Folder"){store.addFolder(name:name)}}
    func tabMenu(_ id:UUID)->NSMenu{
        prepareMutation()
        let menu=NSMenu();guard let tab=store.state.tabs.first(where:{$0.id==id}) else{return menu}
        func add(_ title:String,_ action:@escaping()->Void){menu.addItem(ClosureMenuItem(title:title,action:action))}
        add(tab.pinned ? "Unpin":"Pin"){ [weak self] in self?.rememberEngineURL(id);self?.store.togglePin(id) }
        add(tab.favorite ? "Remove Favorite":"Add to Favorites"){ [weak self] in guard let self else{return};self.rememberEngineURL(id);self.store.moveTab(id,to:self.workspace.activeSpace,pin:true,favorite:!tab.favorite) }
        if let pinned=tab.pinnedURL{add("Reset to Pinned URL"){ [weak self] in self?.store.updateMetadata(tabID:id,url:pinned);self?.engines[id]?.loadURL(pinned) }}
        add("Rename…"){ [weak self] in guard let self,let name=self.textPrompt(title:"Rename tab",value:tab.displayTitle) else{return};self.store.change{s in if let i=s.tabs.firstIndex(where:{$0.id==id}){s.tabs[i].customTitle=name}} }
        if tab.customTitle != nil{add("Use Page Title"){[weak self] in self?.store.change{s in if let i=s.tabs.firstIndex(where:{$0.id==id}){s.tabs[i].customTitle=nil}}}}
        let move=NSMenuItem(title:"Move to Space",action:nil,keyEquivalent:""),spaces=NSMenu();move.submenu=spaces
        for space in store.state.spaces where space.id != tab.spaceID{spaces.addItem(ClosureMenuItem(title:space.name){ [weak self] in self?.store.moveTab(id,to:space.id,favorite:false) })};menu.addItem(move);menu.addItem(.separator())
        let folderItem=NSMenuItem(title:"Move to Folder",action:nil,keyEquivalent:""),folders=NSMenu();folderItem.submenu=folders
        folders.addItem(ClosureMenuItem(title:"No Folder"){[weak self] in self?.store.moveTab(id,to:tab.spaceID,folder:nil,pin:tab.pinned,favorite:false)})
        for folder in store.state.folders where folder.spaceID==tab.spaceID{folders.addItem(ClosureMenuItem(title:(folder.parentID==nil ? "":"    ")+folder.name){[weak self] in self?.store.moveTab(id,to:tab.spaceID,folder:folder.id,pin:true,favorite:false)})};menu.addItem(folderItem)
        add(tab.keepAwake ? "Allow Sleeping":"Keep Awake"){ [weak self] in self?.store.change{s in if let i=s.tabs.firstIndex(where:{$0.id==id}){s.tabs[i].keepAwake.toggle()}} }
        add("Sleep Tab"){ [weak self] in self?.sleepTab(id,manual:true) };add("Close Tab"){ [weak self] in self?.closeTab(id) }
        if tab.pinned{add("Remove Pin and Close"){ [weak self] in self?.closeTab(id,removePin:true) }};return menu
    }
    func folderMenu(_ id:UUID)->NSMenu{
        prepareMutation()
        let menu=NSMenu();guard let folder=store.state.folders.first(where:{$0.id==id}) else{return menu}
        menu.addItem(ClosureMenuItem(title:"Rename Folder…"){ [weak self] in guard let self,let name=self.textPrompt(title:"Rename folder",value:folder.name) else{return};self.store.change{s in if let i=s.folders.firstIndex(where:{$0.id==id}){s.folders[i].name=name}} })
        if folder.parentID==nil{menu.addItem(ClosureMenuItem(title:"New Subfolder…"){ [weak self] in guard let self,let name=self.textPrompt(title:"New subfolder") else{return};self.store.addFolder(name:name,parent:id) })}
        let move=NSMenuItem(title:"Move Folder to Space",action:nil,keyEquivalent:""),spaces=NSMenu();move.submenu=spaces;for space in store.state.spaces where space.id != folder.spaceID{spaces.addItem(ClosureMenuItem(title:space.name){[weak self] in self?.store.moveFolder(id,to:space.id)})};menu.addItem(move)
        let siblings=store.state.folders.filter{$0.spaceID==folder.spaceID && $0.parentID==folder.parentID}
        if let i=siblings.firstIndex(where:{$0.id==id}),i>0{menu.addItem(ClosureMenuItem(title:"Move Folder Up"){[weak self] in self?.store.moveFolder(id,to:folder.spaceID,parent:folder.parentID,before:siblings[i-1].id)})}
        if folder.parentID != nil{menu.addItem(ClosureMenuItem(title:"Move to Top Level"){[weak self] in self?.store.moveFolder(id,to:folder.spaceID)})}
        menu.addItem(ClosureMenuItem(title:"Remove Folder, Keep Tabs"){ [weak self] in self?.store.change{s in let childIDs=Set(s.folders.filter{$0.parentID==id}.map(\.id)).union([id]);for i in s.tabs.indices where s.tabs[i].folderID.map({childIDs.contains($0)})==true{s.tabs[i].folderID=nil};s.folders.removeAll{childIDs.contains($0.id)}} });return menu
    }
    func spaceMenu()->NSMenu{
        prepareMutation()
        let menu=NSMenu();for space in store.state.spaces{let item=ClosureMenuItem(title:space.name){ [weak self] in self?.selectSpace(space.id) };item.state=space.id==workspace.activeSpace ? .on:.off;menu.addItem(item)}
        menu.addItem(.separator());menu.addItem(ClosureMenuItem(title:"New Space…"){ [weak self] in self?.newSpace() })
        menu.addItem(ClosureMenuItem(title:"Rename This Space…"){ [weak self] in guard let self,let name=self.textPrompt(title:"Rename Space",value:self.store.state.space.name) else{return};self.store.change{s in if let i=s.spaces.firstIndex(where:{$0.id==s.activeSpace}){s.spaces[i].name=name}} })
        menu.addItem(ClosureMenuItem(title:"Colors & Background…"){ [weak self] in guard let self else{return};self.auxiliary=SpaceAppearanceWindow(browser:self);self.auxiliary?.showWindow(nil) })
        let iconItem=NSMenuItem(title:"Space Icon",action:nil,keyEquivalent:""),icons=NSMenu();iconItem.submenu=icons
        for (name,icon) in [("Planet","planet"),("Sparkle","sparkle"),("Books","books"),("Ghost","ghost-duotone"),("Folder","folder-simple"),("Globe","globe"),("Moon","moon-duotone")]{let item=ClosureMenuItem(title:name){[weak self] in self?.store.change{s in if let i=s.spaces.firstIndex(where:{$0.id==s.activeSpace}){s.spaces[i].icon=icon}}};item.image=VeilIcon.image(icon)?.copy() as? NSImage;item.image?.size=NSSize(width:18,height:18);icons.addItem(item)};menu.addItem(iconItem)
        for (title,delta) in [("Move Space Left",-1),("Move Space Right",1)]{menu.addItem(ClosureMenuItem(title:title){[weak self] in self?.store.change{s in guard let i=s.spaces.firstIndex(where:{$0.id==s.activeSpace}) else{return};let target=i+delta;guard s.spaces.indices.contains(target) else{return};s.spaces.swapAt(i,target)}})}
        if store.state.spaces.count>1{menu.addItem(ClosureMenuItem(title:"Remove This Space, Move Tabs"){ [weak self] in guard let self,let target=self.store.state.spaces.first(where:{$0.id != self.workspace.activeSpace}) else{return};self.store.deleteSpace(self.workspace.activeSpace,moveTo:target.id) })}
        menu.addItem(.separator());menu.addItem(ClosureMenuItem(title:"Settings…"){ [weak self] in self?.showSettings() });return menu
    }
    private func exportWorkspace(){let panel=NSSavePanel();panel.nameFieldStringValue="VEIL Workspace.json";if panel.runModal() == .OK,let url=panel.url{do{try store.export(to:url);showToast("Workspace exported.")}catch{showToast(error.localizedDescription)}}}
    private func saveHTMLPage(){guard let tab=selectedTab else{return};let panel=NSSavePanel();panel.title="Save HTML Page";panel.message="Saves the page HTML. Linked images and other resources remain online.";panel.nameFieldStringValue=String(tab.title.prefix(80)).replacingOccurrences(of:"/",with:"-")+".html";if panel.runModal() == .OK,let url=panel.url{currentEngine?.saveHTML(to:url.path)}}
    func importWorkspace(){
        prepareMutation()
        let panel=NSOpenPanel();panel.title="Import bookmarks or a VEIL workspace";panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
        if panel.runModal() == .OK,let url=panel.url{
            do{let plan=try WorkspaceImport.preview(url:url,existing:store.state);let preview=NSAlert();preview.messageText="Bring these along?";preview.informativeText=plan.summary;preview.addButton(withTitle:"Import");preview.addButton(withTitle:"Cancel");if preview.runModal() == .alertFirstButtonReturn{try WorkspaceImport.apply(plan,to:store);showToast("Imported. Undo is ready.")}}
            catch{showToast(error.localizedDescription)}
        }
    }
    func showLibrary(section:String="History"){auxiliary=LibraryWindow(browser:self,section:section);auxiliary?.showWindow(nil)}
    func showOnboarding(replay:Bool=false){guard !store.isPrivate, replay || !store.state.onboardingComplete else{return};onboarding=OnboardingWindow(browser:self,replay:replay);onboarding?.showWindow(nil);onboarding?.window?.makeKeyAndOrderFront(nil)}
    private func showSettings(){auxiliary=SettingsWindow(browser:self);auxiliary?.showWindow(nil)}
    private func showPerformance(){auxiliary?.close();auxiliary=PerformanceWindow(browser:self);auxiliary?.showWindow(nil)}
    func performanceTabs()->[PerformanceTab]{
        let otherOwners=coordinator?.windows.filter{$0 !== self && $0.store === store} ?? []
        return store.state.tabs.map{tab in
            let live=engines[tab.id] != nil,info=runtime[tab.id] ?? TabRuntime(),reason=info.sleepProtection.reason
            let elsewhere=otherOwners.contains{$0.hasEngine(tab.id)}
            let activity = !live ? (elsewhere ? "Live in another window":"Sleeping"):(closing[tab.id] != nil ? "Parking…":(reason ?? (tab.keepAwake ? "Kept awake":(tab.id==selectedID ? "Active":"Ready to sleep"))))
            return PerformanceTab(id:tab.id,title:title(for:tab.id),space:store.state.spaces.first(where:{$0.id==tab.spaceID})?.name ?? "Space",activity:activity,live:live,keepAwake:tab.keepAwake,canSleep:live && closing[tab.id]==nil && reason==nil && !tab.keepAwake && tab.id != selectedID)
        }
    }
    func setPerformanceKeepAwake(_ id:UUID,value:Bool){guard let i=store.state.tabs.firstIndex(where:{$0.id==id}),store.state.tabs[i].keepAwake != value else{return};store.change{$0.tabs[i].keepAwake=value}}
    func sleepFromPerformance(_ id:UUID){guard performanceTabs().first(where:{$0.id==id})?.canSleep==true else{showToast("That tab is sleeping or protected.");return};sleepTab(id,manual:true)}
    private func optimizeTabs(pressure:Bool=false){guard !windowClosing,store.state.settings.sleepMinutes>0 else{return};let minutes=pressure ? 1:(ProcessInfo.processInfo.isLowPowerModeEnabled ? min(5,store.state.settings.sleepMinutes):store.state.settings.sleepMinutes);let threshold=TimeInterval(minutes*60);for tab in store.state.tabs where tab.id != selectedID && !tab.keepAwake && Date().timeIntervalSince(tab.lastUsed)>threshold{sleepTab(tab.id,manual:false)}}
    private func sleepTab(_ id:UUID,manual:Bool){
        guard let tab=store.state.tabs.first(where:{$0.id==id}),let engine=engines[id],closing[id]==nil else{return};let info=runtime[id] ?? TabRuntime()
        guard info.sleepProtection.reason==nil && !tab.keepAwake else{if manual{showToast("That tab is protected. Finish playback, downloads, or unsaved work first.")};return}
        guard id != selectedID || manual else{return};closing[id] = .sleep;engine.closeBrowser(false)
    }
    var qaLiveCount:Int{engines.count}
    func qaIsSettled(_ id:UUID)->Bool{engines[id]?.ready==true && runtime[id]?.knownState==true && runtime[id]?.loading==false && runtime[id]?.error==nil}
    func qaSleep(_ id:UUID){guard ProcessInfo.processInfo.arguments.contains("--veil-qa") else{return};sleepTab(id,manual:true)}
    func qaDismissCommand(){palette?.dismiss()}
    func qaScript(_ id:UUID,_ script:String){guard ProcessInfo.processInfo.arguments.contains("--veil-qa") else{return};engines[id]?.executeScript(script)}
    func engineView(_ view:VEEngineView,didUpdate state:[String:Any]){
        guard let id=engines.first(where:{$0.value===view})?.key else{return};var info=runtime[id] ?? TabRuntime()
        if let fullscreen=state["webFullscreen"] as? Bool{setWebFullscreen(fullscreen,tab:id);return}
        if let amount=state["swipeAmount"] as? Double{if id==selectedID{swipeFeedback.update(amount:amount,complete:state["swipeComplete"] as? Bool == true,reduceMotion:store.state.settings.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)};return}
        if let title=state["title"] as? String{info.title=String(title.prefix(512));store.updateMetadata(tabID:id,title:title)}
        if let url=state["url"] as? String{info.crashed=false;info.error=nil;if Navigation.isSupportedURL(url){info.url=url};store.updateMetadata(tabID:id,url:url)}
        if let loading=state["loading"] as? Bool{info.loading=loading;if loading{info.error=nil};if !loading,let tab=store.state.tabs.first(where:{$0.id==id}){store.recordVisit(title:tab.title,url:tab.url)}}
        if let data=state["faviconPNG"] as? Data,let page=state["faviconPageURL"] as? String{
            let accepted=store.favicons.save(data,for:page),matches=FaviconStore.origin(page)==FaviconStore.origin(info.url ?? ""),image=NSImage(data:data);image?.isTemplate=false
            if accepted && matches{info.icon=image;info.iconOrigin=FaviconStore.origin(page)}
            if ProcessInfo.processInfo.arguments.contains("--veil-qa"),let diagnostic=try? JSONSerialization.data(withJSONObject:["accepted":accepted,"origin_matches":matches,"decoded":image != nil,"bytes":data.count],options:.prettyPrinted){try? diagnostic.write(to:URL(fileURLWithPath:VEProfileRoot()).appendingPathComponent("qa-favicon-ui.json"),options:.atomic)}
        }
        if let crashed=state["crashed"] as? Bool{info.crashed=crashed;if crashed{info.error="Your tabs and pins are safe. Reload this page to continue."}}
        if let playing=state["playing"] as? Bool{if playing && !info.playing{dismissedMediaID=nil};info.playing=playing};if let dirty=state["dirty"] as? Bool{info.dirty=dirty;info.knownState=true};if let capture=state["capture"] as? Bool{info.capture=capture}
        if let upload=state["upload"] as? Bool{info.upload=upload}
        if let value=state["hasMedia"] as? Bool{info.hasMedia=value};if let value=state["mediaTitle"] as? String{info.mediaTitle=value};if let value=state["mediaArtist"] as? String{info.mediaArtist=value};if let value=state["mediaPrevious"] as? Bool{info.mediaPrevious=value};if let value=state["mediaNext"] as? Bool{info.mediaNext=value};if let value=state["downloadActive"] as? Bool{info.download=value}
        if let download=state["download"] as? [String:Any]{updateDownload(download,tab:id)}
        if let saved=state["savedHTML"] as? Bool{showToast(saved ? "Page HTML saved.":"Couldn't save that page.")}
        if let error=state["loadError"] as? String{let code=state["errorCode"] as? Int ?? 0;info.error=(-299 ... -200).contains(code) ? "This site's certificate could not be verified. A valid secure connection is required.":"\(error). Check the connection and retry."}
        if state["closeCancelled"] as? Bool == true{
            closing[id]=nil;windowClosing=false;bulkCloseQueue=[];coordinator?.cancelQuit()
            if !store.state.tabs.contains(where:{$0.id==id}),var record=tabRecords[id]{if !store.state.spaces.contains(where:{$0.id==record.spaceID}){record.spaceID=workspace.activeSpace;record.folderID=nil};if let folder=record.folderID,!store.state.folders.contains(where:{$0.id==folder}){record.folderID=nil};store.change{$0.tabs.append(record)};selection.selectTab(record)}
            if let callback=sharedCloseCallbacks.removeValue(forKey:id){callback(false)}
        };runtime[id]=info
        if state["ready"] as? Bool == true,closing[id] != nil{view.closeBrowser(false)};if id==selectedID || state["closeCancelled"] as? Bool == true{showSelected()};sidebar.render();refreshToolbar();refreshMedia()
    }
    func engineView(_ view:VEEngineView,openURL url:String){if let safe=Navigation.resolve(url){openURL(safe)}}
    func engineViewDidClose(_ view:VEEngineView){
        guard let id=engines.first(where:{$0.value===view})?.key else{return};engines[id]=nil;view.removeFromSuperview();let reason=closing.removeValue(forKey:id)
        switch reason{
        case .tab(let removePin):finishCloseTab(id,removePin:removePin);closeNextBulkTab()
        case .shared:if let callback=sharedCloseCallbacks.removeValue(forKey:id){callback(true)}
        case .sleep:if selectedID==id{selection.clear();store.change(undoable:false){s in for i in s.spaces.indices where s.spaces[i].lastTab==id{s.spaces[i].lastTab=nil}}};sidebar.render();showToast("Tab parked. Pick it up anytime.")
        case .window:if windowClosing{closeNextWindowEngine()}else{showSelected();sidebar.render()}
        case .none:sidebar.render()
        }
        if let callback=sharedCloseCallbacks.removeValue(forKey:id){callback(true)}
        pruneTabCaches()
        refreshMedia()
    }
    private func refreshMedia(){
        if webFullscreenTab != nil{mediaCard.isHidden=true;return}
        let playing=runtime.first(where:{$0.value.playing && engines[$0.key] != nil})?.key
        let candidate=playing ?? mediaID.flatMap{runtime[$0]?.hasMedia == true && engines[$0] != nil ? $0:nil} ?? runtime.first(where:{$0.value.hasMedia && engines[$0.key] != nil})?.key
        mediaID=candidate
        guard let candidate,let info=runtime[candidate],candidate != dismissedMediaID else{mediaCard.isHidden=true;return}
        mediaCard.update(title:info.mediaTitle,artist:info.mediaArtist.isEmpty ? store.state.tabs.first(where:{$0.id==candidate}).map{Navigation.displayHost($0.url)} ?? "":info.mediaArtist,playing:info.playing,previous:info.mediaPrevious,next:info.mediaNext,muted:info.muted);mediaCard.isHidden=false
    }
    private func mediaAction(_ action:String){
        guard let id=mediaID else{return}
        switch action{
        case "dismiss":dismissedMediaID=id;mediaCard.isHidden=true
        case "source":selectTab(id)
        case "mute":runtime[id]?.muted.toggle();engines[id]?.setAudioMuted(runtime[id]?.muted ?? false);refreshMedia()
        default:engines[id]?.performMediaAction(action)
        }
    }
    private func updateDownload(_ item:[String:Any],tab:UUID){
        guard let engineID=item["id"] as? Int else{return}
        let identifier=downloadRecordIDs[engineID] ?? UUID();downloadRecordIDs[engineID]=identifier;downloadOwners[identifier]=(tab,engineID)
        let name=item["name"] as? String ?? "Download",path=item["path"] as? String ?? ""
        var record=VeilDownload(id:identifier,engineID:engineID,sourceURL:item["url"] as? String,name:name.isEmpty ? URL(fileURLWithPath:path).lastPathComponent:name,path:path,complete:item["complete"] as? Bool ?? false,cancelled:item["cancelled"] as? Bool ?? false,percent:max(0,item["percent"] as? Int ?? 0))
        if let old=store.state.downloads.first(where:{$0.id==identifier}){record.date=old.date;if old==record{return}}
        store.change(undoable:false){s in
            if let index=s.downloads.firstIndex(where:{$0.id==identifier}){s.downloads[index]=record}else{s.downloads.insert(record,at:0)}
            if s.downloads.count>500{s.downloads.removeLast(s.downloads.count-500)}
        }
    }
    func cancelDownload(_ id:UUID){guard let (tab,native)=downloadOwners[id] else{return};engines[tab]?.cancelDownload(native)}
    func retryDownload(_ id:UUID){guard let record=store.state.downloads.first(where:{$0.id==id}),let raw=record.sourceURL,let url=Navigation.resolve(raw) else{return};if let currentEngine{currentEngine.startDownloadURL(url)}else{openURL(url)}}
}
