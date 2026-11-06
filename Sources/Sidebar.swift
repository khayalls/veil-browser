import AppKit

extension NSPasteboard.PasteboardType {static let veilTab=Self("dev.khayal.veil.tab");static let veilFolder=Self("dev.khayal.veil.folder")}
private enum SidebarKind {case heading,tab,folder,newTab}
private struct SidebarEntry {
    var kind:SidebarKind
    var id:UUID?
    var title:String
    var depth=0
    var pinned=false
}
private final class SidebarTable:NSTableView {
    var context:((Int)->NSMenu?)?
    var folderKey:((Int,Bool)->Bool)?
    override func menu(for event:NSEvent)->NSMenu? {context?(row(at:convert(event.locationInWindow,from:nil)))}
    override func keyDown(with event:NSEvent){
        if event.keyCode==109,event.modifierFlags.contains(.shift),selectedRow>=0,let menu=context?(selectedRow){let rect=rect(ofRow:selectedRow);menu.popUp(positioning:nil,at:NSPoint(x:bounds.midX,y:rect.midY),in:self);return}
        if event.keyCode==123 || event.keyCode==124,folderKey?(selectedRow,event.keyCode==123)==true{return}
        super.keyDown(with:event)
    }
}
private final class SidebarRow:NSTableRowView {
    var selectedTab=false {didSet{needsDisplay=true}}
    var hovered=false
    private var tracking:NSTrackingArea?
    override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking{removeTrackingArea(tracking)};let t=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self);addTrackingArea(t);tracking=t}
    override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
    override func drawBackground(in dirtyRect:NSRect){
        guard selectedTab || hovered else{return}
        NSColor.labelColor.withAlphaComponent(selectedTab ? 0.12:0.055).setFill()
        NSBezierPath(roundedRect:bounds.insetBy(dx:3,dy:1),xRadius:8,yRadius:8).fill()
    }
    override func drawSelection(in dirtyRect:NSRect){}
}
private final class SidebarCell:NSTableCellView {
    let icon=NSImageView(),label=veilLabel(""),status=veilLabel("",size:10,color:.tertiaryLabelColor)
    let close:ActionButton
    var depth:CGFloat=0
    var closeAllowed=false
    private var tracking:NSTrackingArea?
    init(close:@escaping()->Void){
        self.close=ActionButton(icon:"x",help:"Close tab",action:close)
        super.init(frame:.zero)
        [icon,label,status,self.close].forEach{addSubview($0)}
        icon.contentTintColor = .secondaryLabelColor;self.close.isHidden=true
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){super.layout();icon.frame=NSRect(x:12+depth,y:bounds.midY-8,width:16,height:16);label.frame=NSRect(x:36+depth,y:bounds.midY-10,width:max(10,bounds.width-78-depth),height:20);close.frame=NSRect(x:bounds.width-32,y:bounds.midY-11,width:22,height:22);status.frame=NSRect(x:bounds.width-51,y:bounds.midY-8,width:16,height:16)}
    override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking{removeTrackingArea(tracking)};let t=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self);addTrackingArea(t);tracking=t}
    override func mouseEntered(with event:NSEvent){close.isHidden = !closeAllowed;status.isHidden=closeAllowed}
    override func mouseExited(with event:NSEvent){close.isHidden=true;status.isHidden=false}
}
private final class FavoriteTile:NSControl,NSDraggingSource {
    var tabID:UUID?
    var onOpen:(()->Void)?
    var onMenu:(()->NSMenu)?
    var onDrop:((NSPasteboard)->Bool)?
    var icon:NSImage?
    var hasSiteIcon=false
    private let iconView=NSImageView()
    var selected=false
    private var hover=false
    private var tracking:NSTrackingArea?
    override var acceptsFirstResponder:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);registerForDraggedTypes([.veilTab,.URL,.string]);iconView.contentTintColor = .secondaryLabelColor;addSubview(iconView)}
    required init?(coder:NSCoder){fatalError()}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation{hover=true;needsDisplay=true;return .move}
    override func draggingExited(_ sender:NSDraggingInfo?){hover=false;needsDisplay=true}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool{hover=false;needsDisplay=true;return onDrop?(sender.draggingPasteboard) ?? false}
    override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking{removeTrackingArea(tracking)};let t=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self);addTrackingArea(t);tracking=t}
    override func mouseEntered(with event:NSEvent){hover=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hover=false;needsDisplay=true}
    override func draw(_ dirtyRect:NSRect){
        NSColor.labelColor.withAlphaComponent(selected ? 0.14:(hover ? 0.10:0.055)).setFill();NSBezierPath(roundedRect:bounds.insetBy(dx:2,dy:2),xRadius:12,yRadius:12).fill()
        iconView.image=icon;iconView.contentTintColor=hasSiteIcon ? nil:.secondaryLabelColor
    }
    override func layout(){super.layout();iconView.frame=NSRect(x:bounds.midX-10,y:bounds.midY-10,width:20,height:20)}
    override func menu(for event:NSEvent)->NSMenu?{onMenu?()}
    override func keyDown(with event:NSEvent){if event.keyCode==36 || event.keyCode==49{onOpen?()}else{super.keyDown(with:event)}}
    override func mouseDown(with event:NSEvent){
        guard let window else{return}
        let start=event.locationInWindow
        while let next=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            if next.type == .leftMouseUp {onOpen?();return}
            if hypot(next.locationInWindow.x-start.x,next.locationInWindow.y-start.y)>4,let tabID {
                let paste=NSPasteboardItem();paste.setString(tabID.uuidString,forType:.veilTab)
                let item=NSDraggingItem(pasteboardWriter:paste);item.setDraggingFrame(bounds,contents:icon)
                beginDraggingSession(with:[item],event:event,source:self);return
            }
        }
    }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation{.move}
    override func accessibilityPerformPress()->Bool{onOpen?();return true}
}
private final class SidebarDropZone:FlippedView {
    var onDrop:((NSPasteboard)->Bool)?
    var isEmpty=true{didSet{hint.isHidden = !isEmpty;needsDisplay=true}}
    private let hint=veilLabel("Drop a favorite here",size:11,color:.secondaryLabelColor)
    private var dragHover=false
    override init(frame:NSRect){super.init(frame:frame);registerForDraggedTypes([.veilTab,.URL,.string]);hint.alignment = .center;hint.setAccessibilityLabel("Favorites. Drop a tab here, or choose Add to Favorites from its menu.");addSubview(hint)}
    required init?(coder:NSCoder){fatalError()}
    override func layout(){super.layout();hint.frame=NSRect(x:8,y:bounds.midY-9,width:max(0,bounds.width-16),height:18)}
    override func draw(_ rect:NSRect){guard isEmpty || dragHover else{return};let path=NSBezierPath(roundedRect:bounds.insetBy(dx:3,dy:3),xRadius:10,yRadius:10);NSColor.labelColor.withAlphaComponent(dragHover ? 0.10:0.035).setFill();path.fill();if dragHover{NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke();path.lineWidth=1;path.stroke()}}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation{dragHover=true;needsDisplay=true;return .move}
    override func draggingExited(_ sender:NSDraggingInfo?){dragHover=false;needsDisplay=true}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool{dragHover=false;needsDisplay=true;return onDrop?(sender.draggingPasteboard) ?? false}
}
final class SidebarView:FlippedView,NSTableViewDataSource,NSTableViewDelegate {
    weak var owner:BrowserWindowController?
    private let heading=veilLabel("Personal",size:13,weight:.semibold)
    private let spaceIcon=NSImageView()
    private let favorites=SidebarDropZone()
    private let scroll=NSScrollView()
    private let table=SidebarTable()
    private let footer=FlippedView()
    private var entries:[SidebarEntry]=[]
    private var suppressSelection=false
    private var favoriteHeight:CGFloat=0
    init(owner:BrowserWindowController){
        self.owner=owner;super.init(frame:.zero)
        [spaceIcon,heading,favorites,scroll,footer].forEach{addSubview($0)}
        spaceIcon.image=VeilIcon.image("planet-duotone")
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("tabs"));table.addTableColumn(column)
        table.headerView=nil;table.backgroundColor = .clear;table.intercellSpacing = .zero
        table.style = .plain;table.focusRingType = .none;table.selectionHighlightStyle = .none
        table.dataSource=self;table.delegate=self;table.target=self;table.action=#selector(clicked)
        table.setAccessibilityIdentifier("veil.sidebar.tabs")
        table.registerForDraggedTypes([.veilTab,.veilFolder,.URL,.string]);table.setDraggingSourceOperationMask(.move,forLocal:true)
        table.context={ [weak self] row in guard let self,self.entries.indices.contains(row),let owner=self.owner else{return nil};let entry=self.entries[row];switch entry.kind{case .tab:return entry.id.map{owner.tabMenu($0)};case .folder:return entry.id.map{owner.folderMenu($0)};default:return owner.spaceMenu()}}
        table.folderKey={ [weak self] row,collapsed in guard let self,self.entries.indices.contains(row),self.entries[row].kind == .folder,let id=self.entries[row].id else{return false};self.owner?.setFolder(id,collapsed:collapsed);return true }
        scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false
        favorites.onDrop={ [weak self] paste in self?.dropFavorite(paste) ?? false }
        render()
    }
    required init?(coder:NSCoder){fatalError()}
    func render(){
        guard let owner else{return}
        let state=owner.workspace;heading.stringValue=state.space.name+(owner.store.isPrivate ? " · Private":"")
        spaceIcon.image=VeilIcon.image(state.space.icon)
        spaceIcon.contentTintColor=VeilPalette.accent(state.space)
        let selected=owner.selectedID
        entries=[]
        let pinned=state.tabs.filter{$0.spaceID==state.activeSpace && $0.pinned && !$0.favorite}
        let folders=state.folders.filter{$0.spaceID==state.activeSpace}
        if !pinned.isEmpty || !folders.isEmpty {
            entries.append(SidebarEntry(kind:.heading,title:"PINNED"))
            for tab in pinned where tab.folderID==nil{entries.append(SidebarEntry(kind:.tab,id:tab.id,title:owner.title(for:tab.id),pinned:true))}
            func appendFolder(_ folder:VeilFolder,depth:Int){
                entries.append(SidebarEntry(kind:.folder,id:folder.id,title:folder.name,depth:depth,pinned:true))
                if !folder.collapsed {
                    for child in folders where child.parentID==folder.id{appendFolder(child,depth:depth+1)}
                    for tab in pinned where tab.folderID==folder.id{entries.append(SidebarEntry(kind:.tab,id:tab.id,title:owner.title(for:tab.id),depth:depth+1,pinned:true))}
                }
            }
            for folder in folders where folder.parentID==nil{appendFolder(folder,depth:0)}
        }
        entries.append(SidebarEntry(kind:.newTab,title:"New Tab"))
        for tab in state.tabs where tab.spaceID==state.activeSpace && !tab.pinned{entries.append(SidebarEntry(kind:.tab,id:tab.id,title:owner.title(for:tab.id)))}
        let offset=scroll.contentView.bounds.origin
        suppressSelection=true;table.reloadData()
        if let selected,let row=entries.firstIndex(where:{$0.id==selected && $0.kind == .tab}){table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}else{table.deselectAll(nil)}
        scroll.contentView.scroll(to:offset);suppressSelection=false
        favorites.subviews.filter{$0 is FavoriteTile}.forEach{$0.removeFromSuperview()}
        let favoritesList=state.tabs.filter(\.favorite)
        favorites.isEmpty=favoritesList.isEmpty
        let columns=max(2,min(4,Int((max(bounds.width,232)-8)/65)))
        for (index,tab) in favoritesList.enumerated(){
            let tile=FavoriteTile();tile.tabID=tab.id;let siteIcon=owner.favicon(for:tab.id);tile.icon=siteIcon ?? VeilIcon.image("globe");tile.hasSiteIcon=siteIcon != nil
            tile.selected=tab.id==selected;tile.toolTip=owner.title(for:tab.id)+"\n"+Navigation.displayHost(tab.url)
            tile.setAccessibilityElement(true);tile.setAccessibilityRole(.button);tile.setAccessibilityLabel(owner.title(for:tab.id))
            tile.setAccessibilityIdentifier("veil.favorite.\(tab.id.uuidString)")
            tile.onOpen={ [weak owner] in owner?.selectTab(tab.id) };tile.onMenu={ [weak owner] in owner?.tabMenu(tab.id) ?? NSMenu() }
            tile.onDrop={ [weak self] paste in self?.dropFavorite(paste,before:tab.id) ?? false }
            tile.tag=index;favorites.addSubview(tile)
        }
        favoriteHeight=favoritesList.isEmpty ? 58:CGFloat((favoritesList.count+columns-1)/columns)*58+10
        footer.subviews.forEach{$0.removeFromSuperview()}
        let library=ActionButton(icon:"books",help:"Library"){ [weak owner] in owner?.showLibrary() };library.frame=NSRect(x:3,y:2,width:32,height:32);footer.addSubview(library)
        var visible=Array(state.spaces.prefix(4))
        if !visible.contains(where:{$0.id==state.activeSpace}){visible[visible.count-1]=state.space}
        for (index,space) in visible.enumerated(){
            let button=ActionButton(icon:space.icon,help:space.name){ [weak owner] in owner?.selectSpace(space.id) }
            button.accent=VeilPalette.accent(space);button.contentTintColor=button.accent;button.selectedState=space.id==state.activeSpace
            button.frame=NSRect(x:42+CGFloat(index)*33,y:2,width:29,height:32);footer.addSubview(button)
            button.onDragHover={ [weak owner] in owner?.selectSpace(space.id) }
            button.onDrop={ [weak owner] paste in
                guard let owner else{return false};owner.prepareMutation()
                if let raw=paste.string(forType:.veilFolder),let id=UUID(uuidString:raw){return owner.store.moveFolder(id,to:space.id)}
                if let raw=paste.string(forType:.veilTab),let id=UUID(uuidString:raw),owner.store.state.tabs.contains(where:{$0.id==id}){owner.store.moveTab(id,to:space.id,favorite:false);owner.selectTab(id);return true}
                if let raw=paste.string(forType:.URL) ?? paste.string(forType:.string),let url=Navigation.resolve(raw){owner.selectSpace(space.id);owner.openURL(url);return true}
                return false
            }
        }
        let more=ActionButton(icon:"plus",help:"Spaces and settings"){ [weak owner,weak self] in guard let self,let owner else{return};let menu=owner.spaceMenu();menu.popUp(positioning:nil,at:NSPoint(x:self.bounds.width-30,y:self.bounds.height-40),in:self) }
        more.identifier=NSUserInterfaceItemIdentifier("spaces-more");footer.addSubview(more)
        needsLayout=true
    }
    override func layout(){
        super.layout();spaceIcon.frame=NSRect(x:14,y:14,width:20,height:20);heading.frame=NSRect(x:44,y:12,width:bounds.width-58,height:24)
        favorites.frame=NSRect(x:5,y:50,width:bounds.width-10,height:favoriteHeight)
        let columns=max(2,min(4,Int((max(bounds.width,232)-8)/65))),tileWidth=(favorites.bounds.width-8)/CGFloat(columns)
        let tiles=favorites.subviews.compactMap{$0 as? FavoriteTile}
        favoriteHeight=tiles.isEmpty ? 58:CGFloat((tiles.count+columns-1)/columns)*58+10
        favorites.frame.size.height=favoriteHeight
        for tile in tiles{let index=tile.tag;tile.frame=NSRect(x:4+CGFloat(index%columns)*tileWidth,y:CGFloat(index/columns)*58,width:tileWidth-4,height:54)}
        scroll.frame=NSRect(x:2,y:50+favoriteHeight,width:bounds.width-4,height:max(0,bounds.height-100-favoriteHeight))
        table.tableColumns.first?.width=scroll.contentSize.width
        footer.frame=NSRect(x:6,y:bounds.height-44,width:bounds.width-12,height:38)
        footer.subviews.last?.frame=NSRect(x:footer.bounds.width-32,y:2,width:30,height:32)
    }
    func numberOfRows(in tableView:NSTableView)->Int{entries.count}
    func tableView(_ tableView:NSTableView,heightOfRow row:Int)->CGFloat{entries[row].kind == .heading ? 26:(owner?.store.state.settings.compact == true ? 31:37)}
    func tableView(_ tableView:NSTableView,shouldSelectRow row:Int)->Bool{entries[row].kind == .tab || entries[row].kind == .folder}
    func tableView(_ tableView:NSTableView,rowViewForRow row:Int)->NSTableRowView?{let view=SidebarRow();view.selectedTab=entries[row].kind == .tab && entries[row].id==owner?.selectedID;return view}
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView?{
        let entry=entries[row]
        if entry.kind == .heading {let label=veilLabel(entry.title,size:9,weight:.semibold,color:.tertiaryLabelColor);let v=NSTableCellView();label.frame=NSRect(x:14,y:3,width:180,height:17);v.addSubview(label);return v}
        let cell=SidebarCell{ [weak self] in if let id=entry.id{self?.owner?.closeTab(id)} }
        cell.depth=CGFloat(entry.depth)*14;cell.label.stringValue=entry.title;cell.toolTip=entry.title
        if entry.kind == .newTab{cell.icon.image=VeilIcon.image("plus");cell.label.textColor = .secondaryLabelColor;cell.setAccessibilityLabel("New Tab, Command T")}
        if entry.kind == .folder {
            let collapsed=owner?.store.state.folders.first(where:{$0.id==entry.id})?.collapsed ?? true
            cell.icon.image=VeilIcon.image(collapsed ? "caret-right":"folder-simple");cell.label.font = .systemFont(ofSize:12,weight:.medium)
            cell.setAccessibilityLabel(entry.title+", folder, "+(collapsed ? "collapsed":"expanded"))
        }
        if entry.kind == .tab,let id=entry.id,let tab=owner?.store.state.tabs.first(where:{$0.id==id}){
            let siteIcon=owner?.favicon(for:id);cell.icon.image=siteIcon ?? VeilIcon.image("globe");cell.icon.contentTintColor=siteIcon==nil ? .secondaryLabelColor:nil;cell.closeAllowed=true
            cell.toolTip=(owner?.title(for:id) ?? tab.title)+"\n"+tab.url
            if owner?.isSleeping(id)==true{cell.status.stringValue="z";cell.label.textColor = .secondaryLabelColor}
            if owner?.isPlaying(id)==true{cell.status.stringValue="♪"}
            cell.setAccessibilityLabel((owner?.title(for:tab.id) ?? tab.displayTitle)+(tab.pinned ? ", pinned":"")+(owner?.isSleeping(id)==true ? ", sleeping":""))
            cell.setAccessibilityIdentifier("veil.tab.\(id.uuidString)")
        }
        return cell
    }
    @objc private func clicked(){
        let row=table.clickedRow;guard entries.indices.contains(row) else{return}
        let entry=entries[row]
        if entry.kind == .newTab{owner?.showCommandBar();return}
        if entry.kind == .folder,let id=entry.id,let folder=owner?.store.state.folders.first(where:{$0.id==id}){owner?.setFolder(id,collapsed:!folder.collapsed)}
    }
    func tableViewSelectionDidChange(_ notification:Notification){guard !suppressSelection,entries.indices.contains(table.selectedRow) else{return};let entry=entries[table.selectedRow];if entry.kind == .tab,let id=entry.id{owner?.selectTab(id)}}
    func tableView(_ tableView:NSTableView,pasteboardWriterForRow row:Int)->NSPasteboardWriting?{guard entries.indices.contains(row),[SidebarKind.tab,.folder].contains(entries[row].kind),let id=entries[row].id else{return nil};let item=NSPasteboardItem();item.setString(id.uuidString,forType:entries[row].kind == .folder ? .veilFolder:.veilTab);return item}
    func tableView(_ tableView:NSTableView,validateDrop info:NSDraggingInfo,proposedRow row:Int,proposedDropOperation operation:NSTableView.DropOperation)->NSDragOperation {
        if let raw=info.draggingPasteboard.string(forType:.veilFolder),let id=UUID(uuidString:raw),let owner{
            let target=entries.indices.contains(row) ? entries[row]:nil
            let parent=target?.kind == .folder && operation == .on ? target?.id:nil
            let before=target?.kind == .folder && operation == .above ? target?.id:nil
            guard owner.store.canMoveFolder(id,to:owner.workspace.activeSpace,parent:parent,before:before) else{return []};return .move
        }
        if let raw=info.draggingPasteboard.string(forType:.veilTab),let id=UUID(uuidString:raw),owner?.store.state.tabs.contains(where:{$0.id==id}) != true{return []}
        if row>=0,row<entries.count,entries[row].kind == .folder {tableView.setDropRow(row,dropOperation:.on)}else{tableView.setDropRow(max(0,row),dropOperation:.above)}
        return .move
    }
    func tableView(_ tableView:NSTableView,acceptDrop info:NSDraggingInfo,row:Int,dropOperation operation:NSTableView.DropOperation)->Bool{
        guard let owner else{return false};owner.prepareMutation()
        let entry=entries.indices.contains(row) ? entries[row]:nil
        if let raw=info.draggingPasteboard.string(forType:.veilFolder),let id=UUID(uuidString:raw){let parent=entry?.kind == .folder && operation == .on ? entry?.id:nil;let before=entry?.kind == .folder && operation == .above ? entry?.id:nil;return owner.store.moveFolder(id,to:owner.workspace.activeSpace,parent:parent,before:before)}
        let folder=entry?.kind == .folder ? entry?.id:(entry?.id.flatMap{id in owner.store.state.tabs.first(where:{$0.id==id})?.folderID})
        let before=entry?.kind == .tab ? entry?.id:nil
        let pin=folder != nil || entry?.pinned == true || entry?.kind == .heading || entry?.kind == .newTab
        if let raw=info.draggingPasteboard.string(forType:.veilTab),let id=UUID(uuidString:raw){owner.store.moveTab(id,to:owner.workspace.activeSpace,folder:folder,before:before,pin:pin,favorite:false);return true}
        if let raw=info.draggingPasteboard.string(forType:.URL) ?? info.draggingPasteboard.string(forType:.string),let url=Navigation.resolve(raw){let id=owner.openURL(url);owner.store.moveTab(id,to:owner.workspace.activeSpace,folder:folder,before:before,pin:pin);return true}
        return false
    }
    private func dropFavorite(_ paste:NSPasteboard,before:UUID?=nil)->Bool {
        guard let owner else{return false};owner.prepareMutation()
        if let raw=paste.string(forType:.veilTab),let id=UUID(uuidString:raw),owner.store.state.tabs.contains(where:{$0.id==id}){if id==before{return true};owner.store.moveTab(id,to:owner.workspace.activeSpace,before:before,pin:true,favorite:true);return true}
        if let raw=paste.string(forType:.URL) ?? paste.string(forType:.string),let url=Navigation.resolve(raw){let id=owner.openURL(url);owner.store.moveTab(id,to:owner.workspace.activeSpace,before:before,pin:true,favorite:true);return true}
        return false
    }
}
