import AppKit

struct PerformanceTab:Equatable {
    let id:UUID,title:String,space:String,activity:String
    let live:Bool,keepAwake:Bool,canSleep:Bool
}
private final class PerformanceToggle:NSButton {
    var onToggle:((Bool)->Void)?
    init(checked:Bool,action:@escaping(Bool)->Void){
        super.init(frame:.zero);setButtonType(.switch);title="Keep awake";state=checked ? .on:.off;target=self;self.action=#selector(changed);onToggle=action
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func changed(){onToggle?(state == .on)}
}

final class PerformanceWindow:NSWindowController,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate {
    private weak var browser:BrowserWindowController?
    private let titleLabel=veilLabel("Room to breathe.",size:23,weight:.semibold)
    private let subtitle=veilLabel("VEIL and its helpers · live measurements",size:12,color:.secondaryLabelColor)
    private let cpuTitle=veilLabel("CPU",size:12,color:.secondaryLabelColor),memoryTitle=veilLabel("Memory",size:12,color:.secondaryLabelColor)
    private let cpu=veilLabel("Measuring…",size:26,weight:.medium),memory=veilLabel("—",size:26,weight:.medium)
    private let summary=veilLabel("",size:12,color:.secondaryLabelColor)
    private let footnote=veilLabel("Active tabs, media, calls, downloads and unsaved work stay protected.",size:11,color:.secondaryLabelColor)
    private let table=NSTableView(),scroll=NSScrollView()
    private var rows:[PerformanceTab]=[]
    private var observer:UUID?,timer:Timer?,previous:ProcessResourceReading?
    private let queue=DispatchQueue(label:"dev.khayal.veil.resources",qos:.utility)
    private var generation=0,sampling=false
    private var ownerStore:WorkspaceStore?
    init(browser:BrowserWindowController){
        self.browser=browser;ownerStore=browser.store
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:780,height:580),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="Performance";window.minSize=NSSize(width:720,height:440);window.isReleasedWhenClosed=false
        super.init(window:window);window.delegate=self;window.center();window.appearance=browser.window?.effectiveAppearance
        let root=FlippedView();window.contentView=root;root.onLayout={[weak self] in self?.layout()}
        [titleLabel,subtitle,cpuTitle,memoryTitle,cpu,memory,summary,scroll,footnote].forEach{root.addSubview($0)}
        cpu.setAccessibilityIdentifier("veil.performance.cpu");memory.setAccessibilityIdentifier("veil.performance.memory");summary.setAccessibilityIdentifier("veil.performance.summary")
        cpu.toolTip="100% is one logical CPU core. Includes VEIL and its helper processes."
        memory.toolTip="Approximate total: sum of macOS physical footprints for VEIL and its helpers. Shared allocations can appear in more than one process."
        table.setAccessibilityIdentifier("veil.performance.tabs");table.rowHeight=50;table.style = .plain;table.intercellSpacing = .zero;table.columnAutoresizingStyle = .noColumnAutoresizing;table.allowsColumnResizing=false;table.dataSource=self;table.delegate=self;table.target=self;table.doubleAction=#selector(openSelected)
        for (id,label,width) in [("tab","Tab",CGFloat(300)),("activity","Activity in this window",CGFloat(180)),("keep","",CGFloat(120)),("sleep","",CGFloat(100))]{let c=NSTableColumn(identifier:NSUserInterfaceItemIdentifier(id));c.title=label;c.width=width;table.addTableColumn(c)}
        scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        footnote.maximumNumberOfLines=2;footnote.lineBreakMode = .byWordWrapping
        observer=browser.store.observe{[weak self] in guard let self,self.window?.isVisible==true else{return};self.refreshRows()}
        for name in [NSApplication.didHideNotification,NSApplication.didUnhideNotification]{NotificationCenter.default.addObserver(self,selector:#selector(visibilityChanged),name:name,object:nil)}
        refreshRows()
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{timer?.invalidate();if let observer{ownerStore?.removeObserver(observer)};NotificationCenter.default.removeObserver(self)}
    override func showWindow(_ sender:Any?){super.showWindow(sender);window?.makeKeyAndOrderFront(nil);updateSampling()}
    private var shouldSample:Bool{window?.isVisible==true && window?.isMiniaturized==false && window?.occlusionState.contains(.visible)==true && !NSApp.isHidden}
    @objc private func visibilityChanged(){updateSampling()}
    func windowDidChangeOcclusionState(_ notification:Notification){updateSampling()}
    func windowDidDeminiaturize(_ notification:Notification){updateSampling()}
    func windowDidMiniaturize(_ notification:Notification){updateSampling()}
    func windowWillClose(_ notification:Notification){stopSampling()}
    private func updateSampling(){
        guard shouldSample else{stopSampling();return}
        guard timer==nil else{return};generation+=1;previous=nil;cpu.stringValue="Measuring…"
        let value=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in self?.sample()};value.tolerance=0.5;timer=value;sample()
    }
    private func stopSampling(){timer?.invalidate();timer=nil;generation+=1;previous=nil}
    private func sample(){
        guard shouldSample,!sampling else{return};sampling=true;let request=generation
        queue.async{[weak self] in
            let values=VEProcessResources(),time=ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async{[weak self] in
                guard let self else{return};self.sampling=false
                guard self.generation==request,self.shouldSample else{return}
                self.refreshRows()
                guard let reading=ProcessResourceReading(values:values,time:time) else{self.previous=nil;self.cpu.stringValue="Updating…";self.memory.stringValue="—";return}
                let percent=reading.cpuPercent(since:self.previous);self.previous=reading
                self.cpu.stringValue=percent.map{String(format:"%.1f%%",$0)} ?? "Measuring…"
                self.memory.stringValue=String(format:"~%.0f MiB",Double(reading.footprintBytes)/1_048_576)
                self.subtitle.stringValue="VEIL and its helpers · \(reading.processCount) processes"
                if ProcessInfo.processInfo.arguments.contains("--veil-qa"){
                    let counts=Dictionary(grouping:self.rows,by:{$0.activity}).mapValues(\.count)
                    let object:[String:Any]=["processes":reading.processCount,"footprintBytes":reading.footprintBytes,"cpuPercent":percent.map{NSNumber(value:$0) as Any} ?? NSNull(),"rows":self.rows.count,"activities":counts,"sampledAtUptime":reading.time,"sampling":true]
                    if let data=try? JSONSerialization.data(withJSONObject:object,options:.prettyPrinted){try? data.write(to:URL(fileURLWithPath:VEProfileRoot()).appendingPathComponent("qa-performance.json"),options:.atomic)}
                }
            }
        }
    }
    private func refreshRows(){
        guard let browser else{return};let next=browser.performanceTabs()
        let live=next.filter(\.live).count;summary.stringValue="\(live) live here · \(next.count-live) not loaded here · Tab activity in this window"
        guard next != rows else{return};let selected=rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].id:nil
        rows=next;table.reloadData();if let selected,let i=rows.firstIndex(where:{$0.id==selected}){table.selectRowIndexes(IndexSet(integer:i),byExtendingSelection:false)}
    }
    private func layout(){
        guard let root=window?.contentView else{return};let w=root.bounds.width,h=root.bounds.height
        titleLabel.frame=NSRect(x:24,y:18,width:w-48,height:34);subtitle.frame=NSRect(x:25,y:55,width:w-50,height:22)
        cpuTitle.frame=NSRect(x:26,y:89,width:210,height:18);cpu.frame=NSRect(x:24,y:110,width:260,height:36)
        memoryTitle.frame=NSRect(x:320,y:89,width:250,height:18);memory.frame=NSRect(x:318,y:110,width:300,height:36)
        summary.frame=NSRect(x:25,y:157,width:w-50,height:23)
        scroll.frame=NSRect(x:20,y:193,width:w-40,height:max(120,h-248));footnote.frame=NSRect(x:25,y:h-45,width:w-50,height:36)
        table.tableColumns.first?.width=max(200,scroll.contentSize.width-400)
    }
    func numberOfRows(in tableView:NSTableView)->Int{rows.count}
    func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int)->NSView?{
        let item=rows[row]
        switch column?.identifier.rawValue{
        case "keep":
            let toggle=PerformanceToggle(checked:item.keepAwake){[weak self] value in self?.browser?.setPerformanceKeepAwake(item.id,value:value);self?.refreshRows()};toggle.setAccessibilityIdentifier("veil.performance.keep.\(item.id)");toggle.setAccessibilityLabel("Keep awake: "+item.title);return toggle
        case "sleep":
            let button=ActionButton(icon:"moon",title:" Sleep",help:item.canSleep ? "Unload this tab":"This tab is sleeping or protected"){[weak self] in self?.browser?.sleepFromPerformance(item.id);self?.refreshRows()};button.isEnabled=item.canSleep;button.setAccessibilityIdentifier("veil.performance.sleep.\(item.id)");return button
        case "activity":let cell=FlippedView(),label=veilLabel(item.activity,size:12,color:.secondaryLabelColor);cell.addSubview(label);cell.onLayout={[weak cell,weak label] in guard let cell else{return};label?.frame=NSRect(x:4,y:15,width:cell.bounds.width-8,height:20)};return cell
        default:
            let cell=NSTableCellView(),name=veilLabel(item.title,size:13,weight:.medium),detail=veilLabel(item.space,size:11,color:.secondaryLabelColor)
            let width=tableView.tableColumns.first?.width ?? 300;name.frame=NSRect(x:6,y:26,width:width-12,height:20);detail.frame=NSRect(x:6,y:7,width:width-12,height:17);cell.addSubview(name);cell.addSubview(detail);cell.setAccessibilityLabel(item.title+", "+item.activity);return cell
        }
    }
    @objc private func openSelected(){guard rows.indices.contains(table.selectedRow),let browser else{return};browser.selectTab(rows[table.selectedRow].id);browser.window?.makeKeyAndOrderFront(nil)}
}
