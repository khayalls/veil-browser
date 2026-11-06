import AppKit
import Quartz
import QuickLookThumbnailing

private struct LibraryRecord{
    let title:String,detail:String,icon:String
    var url:String?
    var tabID:UUID?
    var archivedID:UUID?
    var path:String?
    var downloadID:UUID?
}
final class LibraryWindow:NSWindowController,NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate,QLPreviewPanelDataSource{
    private weak var browser:BrowserWindowController?
    private let sections=NSSegmentedControl(labels:["History","Downloads","Saved","Archived"],trackingMode:.selectOne,target:nil,action:nil)
    private let search=NSSearchField(),table=NSTableView(),scroll=NSScrollView()
    private let empty=veilLabel("Nothing here yet.",size:17,weight:.medium,color:.secondaryLabelColor)
    private var records:[LibraryRecord]=[]
    private var observer:UUID?
    private var previewURL:URL?
    private var buttons:[ActionButton]=[]
    private var thumbnails:[String:NSImage]=[:]
    private var thumbnailRequests=Set<String>()
    init(browser:BrowserWindowController,section:String){
        self.browser=browser
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:760,height:560),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="Library";window.minSize=NSSize(width:720,height:420);window.isReleasedWhenClosed=false
        super.init(window:window);window.center()
        let root=FlippedView();window.contentView=root;root.onLayout={ [weak self] in self?.layout() }
        sections.target=self;sections.action=#selector(changed);sections.selectedSegment=["History","Downloads","Saved","Archived"].firstIndex(of:section) ?? 0
        search.placeholderString="Find in your Library";search.delegate=self;search.setAccessibilityIdentifier("veil.library.search")
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("item"));table.addTableColumn(column);table.headerView=nil;table.rowHeight=60;table.style = .plain;table.dataSource=self;table.delegate=self;table.target=self;table.doubleAction=#selector(openSelected)
        table.setAccessibilityIdentifier("veil.library.items");scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        let open=ActionButton(icon:"arrow-square-out",title:" Open",help:"Open selected item"){ [weak self] in self?.openSelected() }
        let preview=ActionButton(icon:"file",title:" Quick Look",help:"Preview selected download"){ [weak self] in self?.previewSelected() }
        let reveal=ActionButton(icon:"folder-simple",title:" Reveal",help:"Reveal selected file in Finder"){ [weak self] in self?.revealSelected() }
        let remove=ActionButton(icon:"trash",title:" Remove Record",help:"Remove Library record, keep files on disk"){ [weak self] in self?.removeSelected() }
        let cancel=ActionButton(icon:"x",title:" Cancel",help:"Cancel selected download"){ [weak self] in guard let self,let id=self.selected?.downloadID else{return};self.browser?.cancelDownload(id) }
        let retry=ActionButton(icon:"arrow-clockwise",title:" Retry",help:"Retry selected download"){ [weak self] in guard let self,let id=self.selected?.downloadID else{return};self.browser?.retryDownload(id) }
        buttons=[open,preview,reveal,remove,cancel,retry]
        [sections,search,scroll,empty].forEach{root.addSubview($0)};buttons.forEach{root.addSubview($0)}
        empty.alignment = .center
        observer=browser.store.observe{ [weak self] in self?.reload() };reload()
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{if let observer{browser?.store.removeObserver(observer)}}
    private func layout(){guard let root=window?.contentView else{return};let w=root.bounds.width,h=root.bounds.height
        sections.frame=NSRect(x:24,y:20,width:400,height:28);search.frame=NSRect(x:w-270,y:20,width:246,height:28)
        scroll.frame=NSRect(x:20,y:66,width:w-40,height:h-130);table.tableColumns.first?.width=scroll.contentSize.width
        empty.frame=NSRect(x:24,y:h/2-20,width:w-48,height:30)
        let widths:[CGFloat]=[70,105,80,125,75,65];var x:CGFloat=24;for (i,button) in buttons.enumerated(){button.frame=NSRect(x:x,y:h-46,width:widths[i],height:30);x+=widths[i]+8}
    }
    @objc private func changed(){reload()}
    func controlTextDidChange(_ obj:Notification){reload()}
    private func reload(){
        guard let state=browser?.store.state else{return};let q=search.stringValue
        switch sections.selectedSegment{
        case 1:records=state.downloads.map{item in let exists=FileManager.default.fileExists(atPath:item.path);let status=item.interrupted==true ? "Interrupted — retry available":(item.cancelled ? "Cancelled":(item.complete ? (exists ? "Downloaded":"File moved or removed"):"\(item.percent)% downloaded"));return LibraryRecord(title:item.name,detail:status+" · "+item.date.formatted(date:.abbreviated,time:.shortened),icon:"file",path:item.path,downloadID:item.id)}
        case 2:records=state.tabs.filter(\.pinned).map{LibraryRecord(title:$0.title,detail:Navigation.displayHost($0.url),icon:$0.favorite ? "sparkle":"push-pin",url:$0.url,tabID:$0.id)}
        case 3:records=state.archive.map{LibraryRecord(title:$0.title,detail:Navigation.displayHost($0.url),icon:"archive",url:$0.url,archivedID:$0.id)}
        default:records=state.history.map{LibraryRecord(title:$0.title,detail:Navigation.displayHost($0.url)+" · "+$0.date.formatted(date:.abbreviated,time:.shortened),icon:"clock-counter-clockwise",url:$0.url)}
        }
        if !q.isEmpty{records=records.filter{$0.title.localizedStandardContains(q)||$0.detail.localizedStandardContains(q)}}
        table.reloadData();empty.isHidden = !records.isEmpty;scroll.isHidden=records.isEmpty
        let downloads=sections.selectedSegment==1;for index in [1,2,4,5]{buttons[index].isHidden = !downloads}
    }
    func numberOfRows(in tableView:NSTableView)->Int{records.count}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{
        let record=records[row],cell=NSTableCellView(),image=NSImageView()
        if let path=record.path,FileManager.default.fileExists(atPath:path){
            image.image=thumbnails[path] ?? NSWorkspace.shared.icon(forFile:path)
            if thumbnails[path]==nil,!thumbnailRequests.contains(path){
                thumbnailRequests.insert(path)
                let request=QLThumbnailGenerator.Request(fileAt:URL(fileURLWithPath:path),size:NSSize(width:64,height:64),scale:2,representationTypes:.thumbnail)
                QLThumbnailGenerator.shared.generateBestRepresentation(for:request){[weak self,weak image] representation,_ in
                    DispatchQueue.main.async{guard let self else{return};if let thumbnail=representation?.nsImage{if self.thumbnails.count>100{self.thumbnails.removeAll()};self.thumbnails[path]=thumbnail;image?.image=thumbnail}}
                }
            }
        }else{image.image=VeilIcon.image(record.icon);image.contentTintColor = .secondaryLabelColor}
        image.frame=NSRect(x:10,y:14,width:32,height:32);cell.addSubview(image)
        let title=veilLabel(record.title,size:13,weight:.medium);title.frame=NSRect(x:58,y:31,width:tableView.bounds.width-80,height:20);cell.addSubview(title)
        let detail=veilLabel(record.detail,size:11,color:.secondaryLabelColor);detail.frame=NSRect(x:58,y:11,width:tableView.bounds.width-80,height:18);cell.addSubview(detail)
        cell.setAccessibilityLabel(record.title+", "+record.detail);return cell
    }
    private var selected:LibraryRecord?{records.indices.contains(table.selectedRow) ? records[table.selectedRow]:nil}
    @objc private func openSelected(){guard let selected,let browser else{return}
        if let tab=selected.tabID{browser.selectTab(tab)}
        else if let id=selected.archivedID,let index=browser.store.state.archive.firstIndex(where:{$0.id==id}){browser.store.change{s in let tab=s.archive.remove(at:index);s.archive.insert(tab,at:0)};if let restored=browser.store.reopenLast(){browser.selectTab(restored)}}
        else if let url=selected.url{browser.openURL(url)}
        else if let path=selected.path,FileManager.default.fileExists(atPath:path){NSWorkspace.shared.open(URL(fileURLWithPath:path))}
    }
    private func revealSelected(){guard let path=selected?.path,FileManager.default.fileExists(atPath:path) else{return};NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:path)])}
    private func previewSelected(){guard let path=selected?.path,FileManager.default.fileExists(atPath:path) else{return};previewURL=URL(fileURLWithPath:path);let panel=QLPreviewPanel.shared();panel?.dataSource=self;panel?.reloadData();panel?.makeKeyAndOrderFront(nil)}
    func numberOfPreviewItems(in panel:QLPreviewPanel!)->Int{previewURL==nil ? 0:1}
    func previewPanel(_ panel:QLPreviewPanel!,previewItemAt index:Int)->(any QLPreviewItem)!{previewURL as NSURL?}
    private func removeSelected(){guard let selected,let browser else{return};browser.store.change{s in
        if let id=selected.downloadID{s.downloads.removeAll{$0.id==id}}
        else if let id=selected.archivedID{s.archive.removeAll{$0.id==id}}
        else if let id=selected.tabID,let i=s.tabs.firstIndex(where:{$0.id==id}){s.tabs[i].pinnedURL=nil;s.tabs[i].favorite=false;s.tabs[i].folderID=nil}
        else if let url=selected.url{s.history.removeAll{$0.url==url}}
    }}
}
