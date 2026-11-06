import AppKit

final class SettingsWindow:NSWindowController,NSWindowDelegate{
    private weak var browser:BrowserWindowController?
    private var draft:VeilSettings
    private let appearance=NSPopUpButton(),search=NSPopUpButton(),sleep=NSPopUpButton()
    private let compact=NSButton(checkboxWithTitle:"Compact sidebar rows",target:nil,action:nil)
    private let material=NSButton(checkboxWithTitle:"Native translucent sidebar",target:nil,action:nil)
    private let motion=NSButton(checkboxWithTitle:"Reduce interface motion",target:nil,action:nil)
    private var labels:[NSTextField]=[]
    private var buttons:[ActionButton]=[]
    private var shortcutWindow:ShortcutsWindow?
    private var appearanceWindow:SpaceAppearanceWindow?
    init(browser:BrowserWindowController){
        self.browser=browser;draft=browser.store.state.settings
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:560,height:500),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="Make VEIL yours";window.isReleasedWhenClosed=false
        super.init(window:window);window.center();window.delegate=self
        let root=FlippedView();window.contentView=root
        let title=veilLabel("Your browser. Your rhythm.",size:23,weight:.semibold);title.frame=NSRect(x:28,y:22,width:500,height:34);root.addSubview(title)
        let detail=veilLabel("Preview a look. Apply when it feels right.",size:12,color:.secondaryLabelColor);detail.frame=NSRect(x:28,y:62,width:500,height:22);root.addSubview(detail)
        appearance.addItems(withTitles:["System","Light","Dark"]);search.addItems(withTitles:["DuckDuckGo","Google"]);sleep.addItems(withTitles:["Never","After 5 minutes","After 15 minutes","After 30 minutes","After 60 minutes"])
        for (index,pair) in [("Appearance",appearance),("Search engine",search),("Sleep inactive tabs",sleep)].enumerated(){let label=veilLabel(pair.0,size:13,weight:.medium);label.frame=NSRect(x:30,y:112+CGFloat(index)*42,width:210,height:24);labels.append(label);root.addSubview(label);pair.1.frame=NSRect(x:270,y:108+CGFloat(index)*42,width:250,height:28);root.addSubview(pair.1)}
        appearance.target=self;appearance.action=#selector(preview)
        for (index,button) in [compact,material,motion].enumerated(){button.frame=NSRect(x:30,y:248+CGFloat(index)*30,width:470,height:24);root.addSubview(button)}
        let reset=ActionButton(icon:"arrow-clockwise",title:" Reset",help:"Reset settings preview"){ [weak self] in self?.draft=VeilSettings();self?.populate();self?.preview() }
        let apply=ActionButton(icon:"check",title:" Apply",help:"Apply settings"){ [weak self] in self?.apply() }
        reset.frame=NSRect(x:28,y:442,width:100,height:32);apply.frame=NSRect(x:422,y:442,width:110,height:32);buttons=[reset,apply];buttons.forEach{root.addSubview($0)}
        let colors=ActionButton(icon:"planet",title:" Colors & Background…",help:"Customize this Space's colors and background"){[weak self,weak browser] in guard let self,let browser else{return};self.appearanceWindow=SpaceAppearanceWindow(browser:browser);self.appearanceWindow?.showWindow(nil)};colors.frame=NSRect(x:28,y:354,width:248,height:34);root.addSubview(colors)
        let shortcuts=ActionButton(icon:"command",title:" Shortcuts…",help:"Customize keyboard shortcuts"){[weak self,weak browser] in guard let self,let browser else{return};self.shortcutWindow=ShortcutsWindow(browser:browser);self.shortcutWindow?.showWindow(nil)};shortcuts.frame=NSRect(x:150,y:442,width:150,height:32);root.addSubview(shortcuts)
        populate()
    }
    required init?(coder:NSCoder){fatalError()}
    private func populate(){appearance.selectItem(at:["system","light","dark"].firstIndex(of:draft.appearance) ?? 0);search.selectItem(withTitle:draft.searchEngine);sleep.selectItem(at:[0,5,15,30,60].firstIndex(of:draft.sleepMinutes) ?? 2);compact.state=draft.compact ? .on:.off;material.state=draft.material ? .on:.off;motion.state=draft.reduceMotion ? .on:.off}
    @objc private func preview(){let value=["system","light","dark"][max(0,appearance.indexOfSelectedItem)];let preview=value=="dark" ? NSAppearance(named:.darkAqua):(value=="light" ? NSAppearance(named:.aqua):nil);window?.appearance=preview;browser?.window?.appearance=preview}
    private func apply(){draft.appearance=["system","light","dark"][max(0,appearance.indexOfSelectedItem)];draft.searchEngine=search.titleOfSelectedItem ?? "DuckDuckGo";draft.sleepMinutes=[0,5,15,30,60][max(0,sleep.indexOfSelectedItem)];draft.compact=compact.state == .on;draft.material=material.state == .on;draft.reduceMotion=motion.state == .on;draft.shortcuts=browser?.store.state.settings.shortcuts ?? draft.shortcuts;browser?.store.change{$0.settings=draft};browser?.showToast("Feels like you. Settings saved.");window?.close()}
    func windowWillClose(_ notification:Notification){let value=browser?.store.state.settings.appearance ?? "system";browser?.window?.appearance=value=="dark" ? NSAppearance(named:.darkAqua):(value=="light" ? NSAppearance(named:.aqua):nil)}
}
