import Foundation

struct VeilSpaceAppearance:Codable,Equatable{
    var accentHex:String?
    var backgroundHex:String?
    var style="gradient"
    var opacity=0.92
    func validate()throws{
        for value in [accentHex,backgroundHex].compactMap({$0}){if value.range(of:"^#[A-Fa-f0-9]{6}$",options:.regularExpression)==nil{throw WorkspaceError.invalid("Invalid theme color")}}
        guard ["solid","gradient"].contains(style),opacity.isFinite,(0.65...1).contains(opacity) else{throw WorkspaceError.invalid("Invalid theme appearance")}
    }
}
struct VeilSpace: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var icon: String = "planet"
    var color: Int = 0
    var lastTab: UUID?
    var appearance:VeilSpaceAppearance?
}
struct VeilFolder: Codable, Equatable, Identifiable {
    var id = UUID()
    var spaceID: UUID
    var parentID: UUID?
    var name: String
    var collapsed = false
}
struct VeilTab: Codable, Equatable, Identifiable {
    var id = UUID()
    var spaceID: UUID
    var folderID: UUID?
    var title: String
    var url: String
    var customTitle:String?
    var pinnedURL: String?
    var favorite = false
    var keepAwake = false
    var created = Date()
    var lastUsed = Date()
    var pinned: Bool { pinnedURL != nil || favorite }
    var displayTitle:String{customTitle ?? title}
}
struct VeilVisit: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var url: String
    var date = Date()
}
struct VeilDownload: Codable, Equatable, Identifiable {
    var id = UUID()
    var engineID: Int
    var sourceURL: String?
    var name: String
    var path: String
    var date = Date()
    var complete = false
    var cancelled = false
    var interrupted:Bool?
    var percent = 0
}
struct VeilSettings: Codable, Equatable {
    var appearance = "system"
    var sidebarWidth: Double = 248
    var compact = false
    var searchEngine = "DuckDuckGo"
    var sleepMinutes = 15
    var reduceMotion = false
    var material = true
    var shortcuts: [String: String] = [:]
}
struct VeilWorkspace: Codable, Equatable {
    var version = 1
    var spaces: [VeilSpace]
    var tabs: [VeilTab] = []
    var folders: [VeilFolder] = []
    var history: [VeilVisit] = []
    var archive: [VeilTab] = []
    var downloads: [VeilDownload] = []
    var activeSpace: UUID
    var settings = VeilSettings()
    var onboardingComplete = false
    var onboardingStep: Int?
    static func fresh() -> Self {
        let personal = VeilSpace(name:"Personal",icon:"planet",color:0)
        return Self(spaces:[personal],activeSpace:personal.id)
    }
    var space: VeilSpace { spaces.first(where:{$0.id == activeSpace}) ?? spaces[0] }
    func visibleTabs(spaceID: UUID? = nil) -> [VeilTab] {
        let id = spaceID ?? activeSpace
        return tabs.filter { $0.favorite || $0.spaceID == id }
    }
    func validate() throws {
        func require(_ condition:Bool,_ message:String) throws {if !condition {throw WorkspaceError.invalid(message)}}
        try require(version == 1,"This workspace needs a newer version of VEIL.")
        let spaceIDs = Set(spaces.map(\.id)), tabIDs = Set(tabs.map(\.id)), folderIDs = Set(folders.map(\.id))
        try require(!spaces.isEmpty && spaceIDs.count == spaces.count && spaceIDs.contains(activeSpace),"Invalid Space structure")
        for space in spaces{try space.appearance?.validate()}
        try require(tabIDs.count == tabs.count && folderIDs.count == folders.count,"Duplicate item identifiers")
        for tab in tabs {
            try require(spaceIDs.contains(tab.spaceID),"Tab without a Space")
            try require(Navigation.isSupportedURL(tab.url) && (tab.pinnedURL.map{Navigation.isSupportedURL($0)} ?? true),"Tab uses an unsupported URL scheme")
            if let id = tab.folderID {
                try require(folders.contains(where:{$0.id == id && $0.spaceID == tab.spaceID}),"Tab in invalid folder")
            }
            try require(!tab.favorite || tab.folderID == nil,"Favorite in a folder")
        }
        for folder in folders {
            try require(spaceIDs.contains(folder.spaceID),"Folder without a Space")
            if let parent = folder.parentID {
                try require(parent != folder.id && folders.contains(where:{$0.id == parent && $0.parentID == nil && $0.spaceID == folder.spaceID}),"Invalid folder depth")
            }
        }
    }
}
enum WorkspaceError: LocalizedError {
    case storage(String), invalid(String)
    var errorDescription: String? {switch self {case .storage(let s),.invalid(let s):return s}}
}

/// All mutations are serialized by the UI thread. Each structural change is one
/// SQLite transaction, then an atomic recovery snapshot. No web secrets live here.
final class WorkspaceStore {
    let favicons:FaviconStore
    private(set) var state: VeilWorkspace
    let directory: URL?
    let isPrivate: Bool
    private var database: OpaquePointer?
    private var observers: [UUID: () -> Void] = [:]
    private var undoStates: [VeilWorkspace] = []
    private var deferredSave: DispatchWorkItem?
    private(set) var recoveryMessage: String?
    var onError: ((Error)->Void)?
    init(directory: URL?, privateMode: Bool = false,initialState:VeilWorkspace?=nil) throws {
        favicons=FaviconStore(directory:privateMode ? nil:directory?.appendingPathComponent("Favicons"))
        self.directory = directory; self.isPrivate = privateMode
        state = .fresh()
        if privateMode {state.onboardingComplete = true;return}
        guard let directory else {throw WorkspaceError.storage("Missing workspace directory")}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
        let path = directory.appendingPathComponent("Workspace.sqlite").path
        guard sqlite3_open_v2(path,&database,SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,nil) == SQLITE_OK else {
            throw WorkspaceError.storage("Could not open workspace storage. Your files have not been changed.")
        }
        do {
            try sql("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS workspace (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL);")
            var statement: OpaquePointer?
            defer {sqlite3_finalize(statement)}
            guard sqlite3_prepare_v2(database,"SELECT payload FROM workspace WHERE id=1",-1,&statement,nil) == SQLITE_OK else {throw error()}
            if sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement,0) {
                let data = Data(bytes:bytes,count:Int(sqlite3_column_bytes(statement,0)))
                state = try JSONDecoder().decode(VeilWorkspace.self,from:data)
                try state.validate()
            } else {if let initialState{try initialState.validate();state=initialState;recoveryMessage="You're using a recovered copy. Your original workspace files are preserved."};try persist()}
        } catch {
            // Leave the original database intact. Recovery is an explicit option,
            // never a silent replacement of an unreadable or newer workspace.
            sqlite3_close(database);database=nil
            throw error
        }
        if state.downloads.contains(where:{!$0.complete && !$0.cancelled}){for i in state.downloads.indices where !state.downloads[i].complete && !state.downloads[i].cancelled{state.downloads[i].cancelled=true;state.downloads[i].interrupted=true};try persist()}
    }
    deinit {deferredSave?.cancel();sqlite3_close(database)}
    @discardableResult func observe(_ body:@escaping ()->Void)->UUID {let id=UUID();observers[id]=body;return id}
    func removeObserver(_ id:UUID) {observers[id]=nil}
    private func notify() {Array(observers.values).forEach{$0()}}
    private func error()->WorkspaceError {.storage(database.map{String(cString:sqlite3_errmsg($0))} ?? "Workspace database is closed")}
    private func sql(_ query:String) throws {guard sqlite3_exec(database,query,nil,nil,nil) == SQLITE_OK else {throw error()}}
    private func persist() throws {
        guard !isPrivate else {return}
        let data=try JSONEncoder().encode(state)
        try sql("BEGIN IMMEDIATE")
        do {
            var statement:OpaquePointer?
            defer {sqlite3_finalize(statement)}
            guard sqlite3_prepare_v2(database,"INSERT INTO workspace(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",-1,&statement,nil) == SQLITE_OK else {throw error()}
            let bindResult=data.withUnsafeBytes {sqlite3_bind_blob(statement,1,$0.baseAddress,Int32($0.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self))}
            guard bindResult == SQLITE_OK,sqlite3_step(statement) == SQLITE_DONE else {throw error()}
            try sql("COMMIT")
        } catch {try? sql("ROLLBACK");throw error}
        // A failed optional snapshot must not roll back an already committed DB.
        if let directory {try? data.write(to:directory.appendingPathComponent("Workspace.backup.json"),options:.atomic)}
    }
    @discardableResult func change(undoable:Bool = true,_ body:(inout VeilWorkspace)throws->Void)->Bool {
        let previous=state
        do {
            try body(&state);try state.validate();try persist()
            if undoable {undoStates.append(previous);if undoStates.count>30 {undoStates.removeFirst()}}
            notify();return true
        } catch {state=previous;onError?(error);return false}
    }
    func updateMetadata(tabID:UUID,title:String?=nil,url:String?=nil) {
        guard let i=state.tabs.firstIndex(where:{$0.id==tabID}) else{return}
        var changed=false
        if let title,!title.isEmpty {let value=String(title.prefix(512));if state.tabs[i].title != value{state.tabs[i].title=value;changed=true}}
        if let url,url.count<=16384,Navigation.isSupportedURL(url),state.tabs[i].url != url{state.tabs[i].url=url;changed=true}
        guard changed else{return}
        notify()
        deferredSave?.cancel()
        let item=DispatchWorkItem { [weak self] in do {try self?.persist()}catch{self?.onError?(error)} }
        deferredSave=item;DispatchQueue.main.asyncAfter(deadline:.now()+0.6,execute:item)
    }
    func flush() {deferredSave?.cancel();do {try persist()}catch{onError?(error)}}
    func undo() {guard let previous=undoStates.popLast() else{return};_ = change(undoable:false){$0=previous}}
    @discardableResult func addTab(url:String,title:String?=nil,pinned:Bool=false,favorite:Bool=false)->UUID {
        let tab=VeilTab(spaceID:state.activeSpace,title:title ?? URL(string:url)?.host ?? url,url:url,pinnedURL:pinned ? url:nil,favorite:favorite)
        _=change {s in s.tabs.append(tab);if let i=s.spaces.firstIndex(where:{$0.id==s.activeSpace}){s.spaces[i].lastTab=tab.id}}
        return tab.id
    }
    func selectTab(_ id:UUID) {
        _=change(undoable:false){s in
            guard let tab=s.tabs.first(where:{$0.id==id}) else{return}
            if !tab.favorite {s.activeSpace=tab.spaceID}
            if let i=s.spaces.firstIndex(where:{$0.id==s.activeSpace}){s.spaces[i].lastTab=id}
            if let i=s.tabs.firstIndex(where:{$0.id==id}){s.tabs[i].lastUsed=Date()}
        }
    }
    func pinPracticeTab(in space:UUID){
        guard state.spaces.contains(where:{$0.id==space}) else{return}
        let address="https://www.apple.com/"
        if let tab=state.tabs.first(where:{($0.favorite || $0.spaceID==space) && Navigation.canonicalURL($0.url)==address}){
            if !tab.pinned{_=change{s in if let i=s.tabs.firstIndex(where:{$0.id==tab.id}){s.tabs[i].pinnedURL=address}}}
        }else{_=change{$0.tabs.append(VeilTab(spaceID:space,title:"Apple",url:address,pinnedURL:address,lastUsed:.distantPast))}}
    }
    func closeTab(_ id:UUID,removePin:Bool=false) {
        guard let tab=state.tabs.first(where:{$0.id==id}) else{return}
        if tab.pinned && !removePin {return} // Closing its renderer is the caller's job.
        _=change{s in
            s.archive.insert(tab,at:0);s.archive=Array(s.archive.prefix(200));s.tabs.removeAll{$0.id==id}
            for i in s.spaces.indices where s.spaces[i].lastTab==id {s.spaces[i].lastTab=nil}
        }
    }
    @discardableResult func reopenLast()->UUID? {
        guard var tab=state.archive.first else{return nil}
        if state.tabs.contains(where:{$0.id==tab.id}){tab.id=UUID()}
        if !state.spaces.contains(where:{$0.id==tab.spaceID}){tab.spaceID=state.activeSpace;tab.folderID=nil}
        if let folder=tab.folderID,!state.folders.contains(where:{$0.id==folder}){tab.folderID=nil}
        let restored=tab
        _=change{s in s.archive.removeFirst();s.tabs.append(restored);s.activeSpace=restored.spaceID;if let i=s.spaces.firstIndex(where:{$0.id==s.activeSpace}){s.spaces[i].lastTab=restored.id}}
        return restored.id
    }
    func togglePin(_ id:UUID) {_=change{s in if let i=s.tabs.firstIndex(where:{$0.id==id}){s.tabs[i].pinnedURL=s.tabs[i].pinned ? nil:s.tabs[i].url;s.tabs[i].favorite=false;if s.tabs[i].pinnedURL==nil{s.tabs[i].folderID=nil}}}}
    func moveTab(_ id:UUID,to space:UUID,folder:UUID?=nil,before:UUID?=nil,pin:Bool?=nil,favorite:Bool?=nil) {
        _=change{s in
            guard let i=s.tabs.firstIndex(where:{$0.id==id}),s.spaces.contains(where:{$0.id==space}) else{return}
            var tab=s.tabs.remove(at:i);tab.spaceID=space;tab.folderID=folder
            if let pin {tab.pinnedURL=pin ? tab.pinnedURL ?? tab.url:nil}
            if let favorite {tab.favorite=favorite;if favorite{tab.folderID=nil;tab.pinnedURL=tab.pinnedURL ?? tab.url}}
            if folder != nil {tab.pinnedURL=tab.pinnedURL ?? tab.url;tab.favorite=false}
            let target=before.flatMap{target in s.tabs.firstIndex(where:{$0.id==target})} ?? s.tabs.count
            s.tabs.insert(tab,at:target)
            for j in s.spaces.indices where s.spaces[j].lastTab==id && s.spaces[j].id != space && !tab.favorite{s.spaces[j].lastTab=nil}
        }
    }
    @discardableResult func addSpace(name:String,color:Int=0)->UUID {
        let space=VeilSpace(name:String(name.prefix(60)),color:color)
        _=change{$0.spaces.append(space);$0.activeSpace=space.id};return space.id
    }
    func selectSpace(_ id:UUID) {_=change(undoable:false){s in if s.spaces.contains(where:{$0.id==id}){s.activeSpace=id}}}
    func deleteSpace(_ id:UUID,moveTo target:UUID) {
        _=change{s in
            guard id != target,s.spaces.count>1,s.spaces.contains(where:{$0.id==target}) else{return}
            for i in s.tabs.indices where s.tabs[i].spaceID==id{s.tabs[i].spaceID=target}
            for i in s.folders.indices where s.folders[i].spaceID==id{s.folders[i].spaceID=target}
            s.spaces.removeAll{$0.id==id};if s.activeSpace==id{s.activeSpace=target}
        }
    }
    @discardableResult func addFolder(name:String,parent:UUID?=nil)->UUID {
        let folder=VeilFolder(spaceID:state.activeSpace,parentID:parent,name:String(name.prefix(100)))
        _=change{$0.folders.append(folder)};return folder.id
    }
    private static func placeFolder(_ state:inout VeilWorkspace,id:UUID,space:UUID,parent:UUID?,before:UUID?)throws{
        guard let index=state.folders.firstIndex(where:{$0.id==id}),state.spaces.contains(where:{$0.id==space}) else{throw WorkspaceError.invalid("Folder or Space not found.")}
        guard id != parent,id != before else{throw WorkspaceError.invalid("A folder cannot contain itself.")}
        let group=Set(state.folders.filter{$0.parentID==id}.map(\.id)).union([id])
        guard parent.map({!group.contains($0)}) ?? true else{throw WorkspaceError.invalid("A folder cannot be moved into its child.")}
        for i in state.folders.indices where group.contains(state.folders[i].id){state.folders[i].spaceID=space}
        state.folders[index].parentID=parent
        let item=state.folders.remove(at:index),target=before.flatMap{b in state.folders.firstIndex(where:{$0.id==b})} ?? state.folders.count;state.folders.insert(item,at:target)
        for i in state.tabs.indices where state.tabs[i].folderID.map({group.contains($0)})==true{state.tabs[i].spaceID=space}
        for i in state.spaces.indices{if let last=state.spaces[i].lastTab,state.tabs.contains(where:{$0.id==last && $0.spaceID != state.spaces[i].id && !$0.favorite}){state.spaces[i].lastTab=nil}}
        try state.validate()
    }
    func canMoveFolder(_ id:UUID,to space:UUID,parent:UUID?=nil,before:UUID?=nil)->Bool{var preview=state;return (try? Self.placeFolder(&preview,id:id,space:space,parent:parent,before:before)) != nil}
    @discardableResult func moveFolder(_ id:UUID,to space:UUID,parent:UUID?=nil,before:UUID?=nil)->Bool{change{s in try Self.placeFolder(&s,id:id,space:space,parent:parent,before:before)}}
    func recordVisit(title:String,url:String) {
        guard !isPrivate,url.hasPrefix("http") else{return}
        if let first=state.history.first,first.url==url,Date().timeIntervalSince(first.date)<30{return}
        _=change(undoable:false){s in
            s.history.insert(VeilVisit(title:String(title.prefix(512)),url:url),at:0);s.history=Array(s.history.prefix(1000))
        }
    }
    func export(to url:URL)throws {
        var portable=state;portable.history=[];portable.downloads=[];portable.archive=[]
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(portable).write(to:url,options:.atomic)
    }
    func importWorkspace(from url:URL)throws {
        let data=try Data(contentsOf:url);guard data.count<10_000_000 else{throw WorkspaceError.invalid("That workspace file is too large.")}
        let imported=try JSONDecoder().decode(VeilWorkspace.self,from:data);try imported.validate()
        // Merge remaps all IDs so existing tabs and history stay intact.
        var spaces:[UUID:UUID]=[:],folders:[UUID:UUID]=[:]
        for item in imported.spaces{spaces[item.id]=UUID()};for item in imported.folders{folders[item.id]=UUID()}
        guard change({s in
            for var item in imported.spaces{item.id=spaces[item.id]!;item.lastTab=nil;s.spaces.append(item)}
            for var item in imported.folders{item.id=folders[item.id]!;item.spaceID=spaces[item.spaceID]!;item.parentID=item.parentID.flatMap{folders[$0]};s.folders.append(item)}
            for var item in imported.tabs{item.id=UUID();item.spaceID=spaces[item.spaceID]!;item.folderID=item.folderID.flatMap{folders[$0]};s.tabs.append(item)}
        }) else{throw WorkspaceError.storage("Could not save the imported workspace.")}
    }
}

enum Navigation {
    static func isSupportedURL(_ address:String)->Bool{if address=="about:blank"{return true};guard let value=URL(string:address),["http","https"].contains(value.scheme?.lowercased() ?? ""),value.host != nil else{return false};return true}
    static func canonicalURL(_ address:String)->String{
        guard var value=URLComponents(string:address) else{return address}
        value.scheme=value.scheme?.lowercased();value.host=value.host?.lowercased();if value.path.isEmpty{value.path="/"};return value.string ?? address
    }
    static func resolve(_ input:String,searchEngine:String="DuckDuckGo")->String? {
        let text=input.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty,text.count<=16384 else{return nil}
        if text=="about:blank" {return text}
        let hasWhitespace=text.rangeOfCharacter(from:.whitespacesAndNewlines) != nil
        let explicit=text.range(of:"^[A-Za-z][A-Za-z0-9+.-]*:",options:.regularExpression) != nil
        let localPort=text.range(of:"^(localhost|[0-9.]+):[0-9]+",options:.regularExpression) != nil
        if explicit && !localPort {
            guard let url=URL(string:text),["http","https"].contains(url.scheme?.lowercased() ?? ""),let host=url.host,!host.isEmpty,!hasWhitespace else{return nil}
            return url.absoluteString
        }
        let first=String(text.split(separator:"/").first ?? "")
        if !hasWhitespace && (first.contains(".") || first.hasPrefix("localhost")) {
            let prefix=first.hasPrefix("localhost") || first.hasPrefix("127.") ? "http://":"https://"
            if let url=URL(string:prefix+text),url.host != nil{return url.absoluteString}
        }
        var components=URLComponents(string:searchEngine=="Google" ? "https://www.google.com/search":"https://duckduckgo.com/")!
        components.queryItems=[URLQueryItem(name:"q",value:text)]
        return components.url?.absoluteString
    }
    static func displayHost(_ address:String)->String {
        guard let url=URL(string:address),let host=url.host else{return address}
        let name=host.hasPrefix("www.") ? String(host.dropFirst(4)):host
        return name+(url.port.map{":\($0)"} ?? "")
    }
}
