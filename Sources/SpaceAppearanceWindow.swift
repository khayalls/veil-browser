import AppKit

final class SpaceAppearanceWindow:NSWindowController,NSWindowDelegate{
    private weak var browser:BrowserWindowController?
    private let space:VeilSpace
    private var draft:VeilSpaceAppearance
    private let accent=NSColorWell(),background=NSColorWell()
    private let style=NSSegmentedControl(labels:["Solid","Soft gradient"],trackingMode:.selectOne,target:nil,action:nil)
    private let opacity=NSSlider(value:92,minValue:65,maxValue:100,target:nil,action:nil)
    private let opacityValue=veilLabel("",size:12,color:.secondaryLabelColor)
    init(browser:BrowserWindowController){
        self.browser=browser;space=browser.workspace.space;draft=space.appearance ?? VeilSpaceAppearance()
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:430),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="Colors & Background";window.isReleasedWhenClosed=false
        super.init(window:window);window.delegate=self;window.center();window.appearance=browser.window?.effectiveAppearance
        let root=FlippedView();window.contentView=root
        let title=veilLabel("A little more you.",size:25,weight:.semibold),subtitle=veilLabel(space.name+" · Colors, background, and glass",size:12,color:.secondaryLabelColor)
        title.frame=NSRect(x:28,y:22,width:480,height:34);subtitle.frame=NSRect(x:30,y:65,width:480,height:22);root.addSubview(title);root.addSubview(subtitle)
        for (index,color) in VeilPalette.accents.enumerated(){let swatch=ActionButton(icon:"planet",help:"Theme color \(index+1)"){[weak self] in guard let self else{return};self.draft.accentHex=VeilPalette.hex(color);self.populate();self.preview()};swatch.contentTintColor=color;swatch.accent=color;swatch.selectedState=true;swatch.frame=NSRect(x:30+CGFloat(index)*55,y:103,width:43,height:35);root.addSubview(swatch)}
        for (label,y) in [("Accent",165.0),("Background",209.0),("Background style",253.0),("Glass opacity",300.0)]{let text=veilLabel(label,size:13,weight:.medium);text.frame=NSRect(x:30,y:y,width:190,height:24);root.addSubview(text)}
        for (well,y,help) in [(accent,161.0,"Accent color"),(background,205.0,"Background color")]{well.colorWellStyle = .minimal;well.frame=NSRect(x:250,y:y,width:248,height:30);well.target=self;well.action=#selector(colorChanged(_:));well.setAccessibilityLabel(help);root.addSubview(well)}
        style.frame=NSRect(x:250,y:251,width:248,height:28);style.target=self;style.action=#selector(styleChanged);root.addSubview(style)
        opacity.frame=NSRect(x:250,y:299,width:194,height:25);opacity.target=self;opacity.action=#selector(opacityChanged);opacity.isContinuous=true;opacity.setAccessibilityLabel("Glass opacity");root.addSubview(opacity)
        opacityValue.frame=NSRect(x:453,y:301,width:45,height:22);opacityValue.alignment = .right;root.addSubview(opacityValue)
        let reset=ActionButton(icon:"arrow-clockwise",title:" Reset theme",help:"Reset this Space's theme"){[weak self] in guard let self else{return};self.draft=VeilSpaceAppearance();self.populate();self.preview()}
        let apply=ActionButton(icon:"check",title:" Apply",help:"Apply colors and background"){[weak self] in self?.apply()}
        reset.frame=NSRect(x:28,y:370,width:130,height:32);apply.frame=NSRect(x:400,y:370,width:110,height:32);root.addSubview(reset);root.addSubview(apply)
        populate()
    }
    required init?(coder:NSCoder){fatalError()}
    private func populate(){accent.color=draft.accentHex.flatMap(VeilPalette.color) ?? VeilPalette.accent(space.color);background.color=draft.backgroundHex.flatMap(VeilPalette.color) ?? .windowBackgroundColor;style.selectedSegment=draft.style=="solid" ? 0:1;opacity.doubleValue=draft.opacity*100;opacityValue.stringValue="\(Int((draft.opacity*100).rounded()))%"}
    @objc private func colorChanged(_ sender:NSColorWell){if sender === accent{draft.accentHex=VeilPalette.hex(accent.color)}else{draft.backgroundHex=VeilPalette.hex(background.color)};preview()}
    @objc private func styleChanged(){draft.style=style.selectedSegment==0 ? "solid":"gradient";preview()}
    @objc private func opacityChanged(){draft.opacity=opacity.doubleValue/100;opacityValue.stringValue="\(Int(opacity.doubleValue.rounded()))%";preview()}
    private func preview(){browser?.previewAppearance(draft,space:space.id)}
    private func apply(){guard let browser else{return};if browser.store.change({s in if let i=s.spaces.firstIndex(where:{$0.id==space.id}){s.spaces[i].appearance=draft}}){browser.showToast("Your Space. Your colors.");window?.close()}}
    func windowWillClose(_ notification:Notification){browser?.previewAppearance(nil,space:space.id)}
}
