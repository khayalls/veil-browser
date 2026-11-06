import AppKit

private final class PracticeTab:NSControl,NSDraggingSource{
    var onPin:(()->Void)?
    private let icon=NSImageView(),label=veilLabel("A tiny tab",size:13,weight:.medium)
    override init(frame:NSRect){super.init(frame:frame);icon.image=VeilIcon.image("globe");icon.contentTintColor = .secondaryLabelColor;addSubview(icon);addSubview(label)}
    required init?(coder:NSCoder){fatalError()}
    override func layout(){super.layout();icon.frame=NSRect(x:20,y:18,width:18,height:18);label.frame=NSRect(x:48,y:17,width:125,height:22)}
    override var acceptsFirstResponder:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        NSColor.labelColor.withAlphaComponent(0.065).setFill();NSBezierPath(roundedRect:bounds,xRadius:12,yRadius:12).fill()
    }
    override func mouseDown(with event:NSEvent){
        guard let window else{return};let start=event.locationInWindow
        while let next=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]){
            if next.type == .leftMouseUp{return}
            if hypot(next.locationInWindow.x-start.x,next.locationInWindow.y-start.y)>4{
                let paste=NSPasteboardItem();paste.setString("https://www.apple.com/",forType:.URL)
                let item=NSDraggingItem(pasteboardWriter:paste);item.setDraggingFrame(bounds,contents:VeilIcon.image("globe"));beginDraggingSession(with:[item],event:event,source:self);return
            }
        }
    }
    override func keyDown(with event:NSEvent){if event.keyCode==36 || event.keyCode==49{onPin?()}else{super.keyDown(with:event)}}
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation{.copy}
    override func accessibilityPerformPress()->Bool{onPin?();return true}
}
final class OnboardingWindow:NSWindowController,NSWindowDelegate{
    private weak var browser:BrowserWindowController?
    private var step:Int
    private let content=FlippedView()
    private let hero=NSImageView(),title=veilLabel("",size:30,weight:.semibold),detail=veilLabel("",size:13,color:.secondaryLabelColor)
    private let stage=FlippedView(),progress=veilLabel("",size:11,color:.tertiaryLabelColor)
    private var next:ActionButton!,skip:ActionButton!,back:ActionButton!
    private var completing=false
    init(browser:BrowserWindowController,replay:Bool=false){
        self.browser=browser;step=replay ? 0:min(3,max(0,browser.store.state.onboardingStep ?? 0))
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:500),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="Welcome to VEIL";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.isReleasedWhenClosed=false
        super.init(window:window);window.delegate=self;window.contentView=content;window.center()
        [hero,title,detail,stage,progress].forEach{content.addSubview($0)}
        title.alignment = .center;detail.alignment = .center;detail.maximumNumberOfLines=2;detail.lineBreakMode = .byWordWrapping
        next=ActionButton(icon:"arrow-right",title:" Set up VEIL",help:"Continue setup"){ [weak self] in self?.advance() }
        skip=ActionButton(icon:"x",title:" Skip for now",help:"Skip setup"){ [weak self] in self?.complete() }
        back=ActionButton(icon:"arrow-left",title:" Back",help:"Previous setup step"){ [weak self] in guard let self,self.step>0 else{return};self.step-=1;self.render() }
        [next!,skip!,back!].forEach{content.addSubview($0)}
        hero.frame=NSRect(x:302,y:34,width:76,height:76);title.frame=NSRect(x:26,y:132,width:628,height:44);detail.frame=NSRect(x:45,y:187,width:590,height:42);stage.frame=NSRect(x:48,y:254,width:584,height:142)
        next.frame=NSRect(x:478,y:438,width:162,height:34);skip.frame=NSRect(x:34,y:438,width:130,height:34);back.frame=NSRect(x:183,y:438,width:83,height:34);progress.frame=NSRect(x:306,y:447,width:100,height:20);progress.alignment = .center
        render()
    }
    required init?(coder:NSCoder){fatalError()}
    private func render(){
        stage.subviews.forEach{$0.removeFromSuperview()};back.isHidden=step==0;progress.stringValue="\(step+1) of 4"
        let titles=["Your tabs, with room to breathe.","Bring your corner of the internet.","Make some space.","Try ⌘T. Go anywhere."]
        let details=["A quiet browser for quick hands and curious minds.","Import an Arc or browser bookmark export, or start fresh.","Choose a color. Give one little tab a home.","Search, switch tabs, and run commands from one floating bar."]
        let icons=["ghost-duotone","books-duotone","planet-duotone","sparkle-duotone"]
        title.stringValue=titles[step];detail.stringValue=details[step];hero.image=VeilIcon.image(icons[step]);hero.contentTintColor=VeilPalette.accent(browser?.workspace.space.color ?? 0)
        next.title=step==3 ? " Let's go":" Continue";if step==0{next.title=" Set up VEIL"}
        if step==0{
            let pill=veilLabel("⌘T to go somewhere     ·     ⌘S for a little more space",size:13,weight:.medium,color:.secondaryLabelColor);pill.alignment = .center;pill.frame=NSRect(x:0,y:43,width:584,height:28);stage.addSubview(pill)
        }else if step==1{
            let button=ActionButton(icon:"arrow-down",title:" Import bookmarks or workspace",help:"Choose a bookmark export file"){ [weak self] in self?.browser?.importWorkspace() };button.frame=NSRect(x:130,y:22,width:324,height:42);stage.addSubview(button)
            let note=veilLabel("No account. No cookie or password import.",size:11,color:.tertiaryLabelColor);note.alignment = .center;note.frame=NSRect(x:0,y:83,width:584,height:24);stage.addSubview(note)
        }else if step==2{
            for (index,color) in VeilPalette.accents.enumerated(){let button=ActionButton(icon:"planet",help:"Space color \(index+1)"){ [weak self] in guard let self,let browser=self.browser else{return};let space=browser.workspace.activeSpace;browser.store.change{s in if let i=s.spaces.firstIndex(where:{$0.id==space}){s.spaces[i].color=index}};self.hero.contentTintColor=color };button.contentTintColor=color;button.frame=NSRect(x:163+CGFloat(index)*43,y:0,width:34,height:32);stage.addSubview(button)}
            let practice=PracticeTab();practice.frame=NSRect(x:80,y:66,width:190,height:54);practice.onPin={ [weak self] in self?.pinPractice() };practice.setAccessibilityElement(true);practice.setAccessibilityRole(.button);practice.setAccessibilityLabel("Practice tab. Drag to pin, or press Return.");stage.addSubview(practice)
            let drop=ActionButton(icon:"push-pin",title:" Drop here to pin",help:"Pin the practice tab"){ [weak self] in self?.pinPractice() };drop.frame=NSRect(x:312,y:66,width:190,height:54);drop.onDrop={ [weak self] paste in guard paste.string(forType:.URL)=="https://www.apple.com/" else{return false};self?.pinPractice();return true };stage.addSubview(drop)
        }else{
            let practice=ActionButton(icon:"command",title:" Open the command bar",help:"Finish setup and open command bar"){ [weak self] in self?.complete(openCommand:true) };practice.frame=NSRect(x:145,y:17,width:294,height:42);stage.addSubview(practice)
            let makeDefault=ActionButton(icon:"globe",title:" Make VEIL my default browser",help:"Ask macOS to make VEIL your default browser"){ [weak self] in self?.makeDefault() };makeDefault.frame=NSRect(x:131,y:78,width:322,height:34);stage.addSubview(makeDefault)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || browser?.store.state.settings.reduceMotion==true{return}
        stage.alphaValue=0;NSAnimationContext.runAnimationGroup{context in context.duration=0.16;stage.animator().alphaValue=1}
    }
    private func pinPractice(){
        guard let browser else{return}
        browser.store.pinPracticeTab(in:browser.workspace.activeSpace)
        detail.stringValue="Pinned. Nice. It will be waiting in your sidebar."
    }
    private func advance(){if step==3{complete();return};step+=1;browser?.store.change(undoable:false){$0.onboardingStep=step};render()}
    private func complete(openCommand:Bool=false){
        completing=true;browser?.store.change(undoable:false){$0.onboardingComplete=true;$0.onboardingStep=3};window?.close();if openCommand{browser?.showCommandBar()}
    }
    func windowWillClose(_ notification:Notification){if !completing{browser?.store.change(undoable:false){$0.onboardingComplete=true}}}
    private func makeDefault(){
        // Only a deliberate product button requests this; automated QA does
        // not change the user's default browser.
        NSWorkspace.shared.setDefaultApplication(at:Bundle.main.bundleURL,toOpenURLsWithScheme:"https"){ [weak self] error in
            DispatchQueue.main.async{self?.detail.stringValue=error==nil ? "macOS has your choice. You can change it anytime.":"You can set VEIL as default later in System Settings."}
        }
        NSWorkspace.shared.setDefaultApplication(at:Bundle.main.bundleURL,toOpenURLsWithScheme:"http"){_ in}
    }
}
