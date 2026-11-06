import AppKit

struct CommandResult {
    let title:String
    let subtitle:String
    let icon:String
    let badge:String
    let action:(()->Void)?
    var image:NSImage?=nil
}
private final class CommandWindow:NSPanel {
    var escape:(()->Void)?
    override var canBecomeKey:Bool{true}
    override var canBecomeMain:Bool{false}
    override func cancelOperation(_ sender:Any?){escape?()}
}
private final class CommandSelectionRow:NSTableRowView {
    override func drawSelection(in dirtyRect:NSRect){
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:4,dy:2),xRadius:9,yRadius:9).fill()
    }
}
final class CommandPanel:NSObject,NSTableViewDataSource,NSTableViewDelegate,NSTextFieldDelegate {
    private let panel=CommandWindow(contentRect:NSRect(x:0,y:0,width:660,height:420),styleMask:[.borderless],backing:.buffered,defer:false)
    private let input=NSTextField()
    private let table=NSTableView()
    private let scroll=NSScrollView()
    var openInNewTab:((String)->Void)?
    private let icon=NSImageView()
    private weak var owner:NSWindow?
    private weak var previousResponder:NSResponder?
    private var outsideMonitor:Any?
    private var escapeMonitor:Any?
    private var results:[CommandResult]=[]
    private let provider:(String)->[CommandResult]
    private let onDismiss:()->Void
    private(set) var isVisible=false
    init(owner:NSWindow,provider:@escaping(String)->[CommandResult],onDismiss:@escaping()->Void) {
        self.owner=owner;self.provider=provider;self.onDismiss=onDismiss
        super.init()
        panel.isReleasedWhenClosed=false;panel.isFloatingPanel=true;panel.hidesOnDeactivate=true
        panel.hasShadow=true;panel.backgroundColor = .clear;panel.isOpaque=false
        panel.collectionBehavior=[.fullScreenAuxiliary]
        panel.escape={ [weak self] in self?.dismiss() }
        for name in [NSWindow.didMoveNotification,NSWindow.didResizeNotification]{NotificationCenter.default.addObserver(self,selector:#selector(ownerMoved),name:name,object:owner)}
        let effect=GlassSurface(radius:28)
        // The glass draws its own rim. Clip the transparent window content to
        // that same shape so its backing surface cannot leave a square edge.
        let backdrop=FlippedView()
        backdrop.wantsLayer=true
        backdrop.layer?.backgroundColor=NSColor.clear.cgColor
        backdrop.layer?.cornerRadius=28
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds=true
        backdrop.addSubview(effect)
        effect.autoresizingMask=[.width,.height]
        panel.contentView=backdrop
        effect.frame=backdrop.bounds
        input.isBordered=false;input.isBezeled=false;input.drawsBackground=false;input.focusRingType = .none
        input.font = .systemFont(ofSize:19,weight:.medium);input.placeholderString="Search or enter URL…"
        input.delegate=self;input.setAccessibilityIdentifier("veil.command.input")
        icon.image=VeilIcon.image("magnifying-glass");icon.contentTintColor = .secondaryLabelColor
        effect.content.addSubview(input);effect.content.addSubview(icon);effect.content.addSubview(scroll)
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("result"));column.width=620;table.addTableColumn(column)
        table.headerView=nil;table.rowHeight=52;table.intercellSpacing = .zero
        table.backgroundColor = .clear;table.focusRingType = .none;table.style = .plain
        table.dataSource=self;table.delegate=self;table.target=self;table.doubleAction=#selector(activate)
        table.setAccessibilityIdentifier("veil.command.results")
        scroll.documentView=table;scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
    }
    deinit{NotificationCenter.default.removeObserver(self)}
    @objc private func ownerMoved(){if isVisible{updateLayout()}}
    func show(initial:String="") {
        guard let owner else{return}
        previousResponder=owner.firstResponder;panel.appearance=owner.effectiveAppearance;input.stringValue=initial;isVisible=true
        results=provider(initial);updateLayout()
        owner.addChildWindow(panel,ordered:.above)
        panel.makeKeyAndOrderFront(nil);panel.makeFirstResponder(input)
        input.selectText(nil)
        if !initial.isEmpty {input.currentEditor()?.selectAll(nil)}
        table.reloadData();selectFirst()
        refreshShadow()
        outsideMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]){ [weak self] event in
            if let self,event.window !== self.panel {self.dismiss()}
            return event
        }
        escapeMonitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){ [weak self] event in
            guard let self,self.isVisible,event.window === self.panel else{return event}
            if event.keyCode==53{self.dismiss();return nil}
            if event.keyCode==36,event.modifierFlags.contains(.command),let action=self.openInNewTab,!self.input.stringValue.isEmpty{let query=self.input.stringValue;self.dismiss();action(query);return nil}
            return event
        }
    }
    func dismiss() {
        guard isVisible else{return};isVisible=false
        if let outsideMonitor{NSEvent.removeMonitor(outsideMonitor);self.outsideMonitor=nil}
        if let escapeMonitor{NSEvent.removeMonitor(escapeMonitor);self.escapeMonitor=nil}
        owner?.removeChildWindow(panel);panel.orderOut(nil)
        owner?.makeKey();if let previousResponder{owner?.makeFirstResponder(previousResponder)}
        onDismiss()
    }
    private func updateLayout(){
        guard let owner else{return}
        let height=CGFloat(min(max(results.count,1),7))*52+82
        let width=min(660,owner.frame.width-80)
        panel.setFrame(NSRect(x:owner.frame.midX-width/2,y:owner.frame.midY-height/2,width:width,height:height),display:true)
        input.frame=NSRect(x:58,y:22,width:width-82,height:30)
        icon.frame=NSRect(x:24,y:27,width:20,height:20)
        scroll.frame=NSRect(x:10,y:70,width:width-20,height:height-82)
        table.tableColumns.first?.width=width-24
        refreshShadow()
        if ProcessInfo.processInfo.arguments.contains("--veil-qa"){
            func rect(_ value:NSRect)->[String:CGFloat]{["x":value.minX,"y":value.minY,"width":value.width,"height":value.height]}
            if let data=try? JSONSerialization.data(withJSONObject:["owner":rect(owner.frame),"panel":rect(panel.frame)],options:.prettyPrinted){try? data.write(to:URL(fileURLWithPath:VEProfileRoot()).appendingPathComponent("qa-command-geometry.json"),options:.atomic)}
        }
    }
    private func refreshShadow(){
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        panel.invalidateShadow()
    }
    private func selectFirst(){if !results.isEmpty{table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)}}
    func advance(_ delta:Int){guard !results.isEmpty else{return};let row=(max(0,table.selectedRow)+delta+results.count)%results.count;table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);table.scrollRowToVisible(row)}
    func commit(){activate()}
    func controlTextDidChange(_ obj:Notification){results=provider(input.stringValue);table.reloadData();updateLayout();selectFirst()}
    func numberOfRows(in tableView:NSTableView)->Int{results.count}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView?{CommandSelectionRow()}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        let result=results[row],cell=NSTableCellView()
        let img=NSImageView();img.image=result.image ?? VeilIcon.image(result.icon);img.contentTintColor=result.image==nil ? .secondaryLabelColor:nil;img.imageScaling = .scaleProportionallyDown
        img.frame=NSRect(x:14,y:16,width:20,height:20);cell.addSubview(img)
        let title=veilLabel(result.title,size:13,weight:.medium)
        let subtitle=result.subtitle=="VEIL command" ? "":result.subtitle
        title.frame=NSRect(x:48,y:subtitle.isEmpty ? 16:25,width:tableView.bounds.width-68,height:20);cell.addSubview(title)
        if !subtitle.isEmpty{let detail=veilLabel(subtitle,size:11,color:.secondaryLabelColor);detail.frame=NSRect(x:48,y:8,width:tableView.bounds.width-68,height:17);cell.addSubview(detail)}
        cell.setAccessibilityLabel(result.title+", "+result.badge)
        return cell
    }
    @objc private func activate(){
        let row=table.selectedRow;guard results.indices.contains(row),let action=results[row].action else{return}
        dismiss();action()
    }
    func control(_ control:NSControl,textView:NSTextView,doCommandBy selector:Selector)->Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            if !results.isEmpty {let row=min(results.count-1,max(0,table.selectedRow+1));table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);table.scrollRowToVisible(row)};return true
        case #selector(NSResponder.moveUp(_:)):
            if !results.isEmpty {let row=max(0,table.selectedRow-1);table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);table.scrollRowToVisible(row)};return true
        case #selector(NSResponder.insertNewline(_:)):activate();return true
        case #selector(NSResponder.cancelOperation(_:)):dismiss();return true
        default:return false
        }
    }
}
