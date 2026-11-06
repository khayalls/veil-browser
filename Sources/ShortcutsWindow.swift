import AppKit

struct ShortcutBinding:Equatable{
    let key:String,flags:NSEvent.ModifierFlags
    init(key:String,flags:NSEvent.ModifierFlags){self.key=key;self.flags=flags.intersection([.command,.control,.option,.shift])}
    init?(_ encoded:String){let parts=encoded.split(separator:":",maxSplits:1,omittingEmptySubsequences:false);guard parts.count==2,let raw=UInt(parts[0]),let data=Data(base64Encoded:String(parts[1])),let key=String(data:data,encoding:.utf8),key.count==1 else{return nil};self.init(key:key,flags:NSEvent.ModifierFlags(rawValue:raw))}
    var encoded:String{"\(flags.rawValue):"+Data(key.utf8).base64EncodedString()}
    var label:String{
        let symbols:[String:String]=["\t":"⇥","\u{f702}":"←","\u{f703}":"→","\u{f700}":"↑","\u{f701}":"↓"," ":"Space"]
        return (flags.contains(.control) ? "⌃":"")+(flags.contains(.option) ? "⌥":"")+(flags.contains(.shift) ? "⇧":"")+(flags.contains(.command) ? "⌘":"")+(symbols[key] ?? key.uppercased())
    }
}
final class ShortcutsWindow:NSWindowController,NSTableViewDataSource,NSTableViewDelegate,NSWindowDelegate{
    private weak var browser:BrowserWindowController?
    private let commands:[VeilCommand]
    private var bindings:[String:String]
    private let table=NSTableView(),scroll=NSScrollView(),status=veilLabel("Select a command, then record a shortcut.",size:12,color:.secondaryLabelColor)
    private var monitor:Any?
    init(browser:BrowserWindowController){
        self.browser=browser;commands=browser.coordinator?.commands ?? [];bindings=browser.store.state.settings.shortcuts
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:580),styleMask:[.titled,.closable],backing:.buffered,defer:false);window.title="Keyboard Shortcuts";window.isReleasedWhenClosed=false
        super.init(window:window);window.center();window.delegate=self;let root=FlippedView();window.contentView=root
        for (id,title,width) in [("command","Command",CGFloat(390)),("shortcut","Shortcut",CGFloat(175))]{let col=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id));col.title=title;col.width=width;table.addTableColumn(col)}
        table.dataSource=self;table.delegate=self;table.rowHeight=29;table.setAccessibilityIdentifier("veil.shortcuts.table");scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.frame=NSRect(x:24,y:24,width:572,height:440);root.addSubview(scroll)
        status.frame=NSRect(x:24,y:477,width:572,height:32);status.maximumNumberOfLines=2;root.addSubview(status)
        let actions:[(String,String,()->Void)]=[("Record","command",{[weak self] in self?.record()}),("Reset Selected","arrow-clockwise",{[weak self] in guard let self,self.commands.indices.contains(self.table.selectedRow) else{return};self.bindings.removeValue(forKey:self.commands[self.table.selectedRow].id);self.table.reloadData()}),("Apply","check",{[weak self] in guard let self else{return};self.stopRecording();self.browser?.store.change{$0.settings.shortcuts=self.bindings};self.browser?.coordinator?.buildMenus();self.window?.close()})]
        for (i,action) in actions.enumerated(){let button=ActionButton(icon:action.1,title:" "+action.0,help:action.0,action:action.2);button.frame=NSRect(x:24+CGFloat(i)*190,y:526,width:172,height:32);root.addSubview(button)}
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{if let monitor{NSEvent.removeMonitor(monitor)}}
    private func binding(_ command:VeilCommand)->ShortcutBinding{bindings[command.id].flatMap{ShortcutBinding($0)} ?? ShortcutBinding(key:command.key,flags:command.modifiers)}
    func numberOfRows(in tableView:NSTableView)->Int{commands.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{let command=commands[row];return veilLabel(tableColumn?.identifier.rawValue=="command" ? command.title:(binding(command).key.isEmpty ? "—":binding(command).label),size:12)}
    private func stopRecording(){if let monitor{NSEvent.removeMonitor(monitor);self.monitor=nil}}
    private func record(){
        guard commands.indices.contains(table.selectedRow) else{return};stopRecording();let id=commands[table.selectedRow].id
        status.stringValue="Press a shortcut with ⌘, ⌃, or ⌥. Escape cancels."
        monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
            guard let self,event.window === self.window else{return event}
            if event.keyCode==53{self.stopRecording();self.status.stringValue="Recording cancelled.";return nil}
            let flags=event.modifierFlags.intersection([.command,.control,.option,.shift]);guard !flags.intersection([.command,.control,.option]).isEmpty,let key=event.charactersIgnoringModifiers?.lowercased(),key.count==1 else{self.status.stringValue="Add ⌘, ⌃, or ⌥ to this shortcut.";return nil}
            let candidate=ShortcutBinding(key:key,flags:flags)
            let reserved:[ShortcutBinding]=["q","h","m","x","c","v","a","z"].map{ShortcutBinding(key:$0,flags:.command)}+[ShortcutBinding(key:"f",flags:[.control,.command])]
            let numeric=Int(key) != nil && (flags == .command || flags == [.control,.option])
            if reserved.contains(candidate) || numeric{self.status.stringValue="That combination belongs to macOS or standard editing.";return nil}
            if let conflict=self.commands.first(where:{$0.id != id && !self.binding($0).key.isEmpty && self.binding($0)==candidate}){self.status.stringValue="Already used by \(conflict.title). Choose another.";return nil}
            self.bindings[id]=candidate.encoded;self.stopRecording();self.table.reloadData();self.status.stringValue="\(candidate.label) recorded. Apply to save.";return nil
        }
    }
    func windowWillClose(_ notification:Notification){stopRecording()}
}
