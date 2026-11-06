import Foundation
import Darwin

@main struct WorkspaceTests {
    final class CacheProbe{}
    struct Failure:Error,CustomStringConvertible {let description:String}
    static func expect(_ value:Bool,_ message:String)throws {if !value{throw Failure(description:message)}}
    static func main() throws {
        if CommandLine.arguments[1]=="--crash-writer"{
            let location=URL(fileURLWithPath:CommandLine.arguments[2]),store=try WorkspaceStore(directory:location)
            let first=store.state.activeSpace,folder=store.addFolder(name:"Pinned work")
            let tabs=(0..<12).map{store.addTab(url:"https://example.com/\($0)",pinned:$0%3==0)}
            store.moveTab(tabs[0],to:first,folder:folder);let other=store.addSpace(name:"Other window")
            store.moveTab(tabs[1],to:other);store.closeTab(tabs[2]);store.pinPracticeTab(in:first)
            try JSONEncoder().encode(store.state).write(to:location.appendingPathComponent("expected-before-kill.json"),options:.atomic)
            raise(SIGSTOP) // Parent sends SIGKILL; no store deinit or graceful flush.
            exit(2)
        }
        let root=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var results:[[String:Any]]=[]
        func test(_ name:String,_ body:()->Void) {body()}
        let cases:[(String,()throws->Void)] = [
            ("Repeated metadata does not invalidate UI or cancel a pending durable update",{
                let location=root.appendingPathComponent("metadata-noop"),s=try WorkspaceStore(directory:location)
                let id=s.addTab(url:"https://example.com",title:"Before");var notifications=0
                let observer=s.observe{notifications+=1};defer{s.removeObserver(observer)}
                s.updateMetadata(tabID:id,title:"After",url:"https://example.com/new")
                for _ in 0..<1000{s.updateMetadata(tabID:id,title:"After",url:"https://example.com/new")}
                try expect(notifications==1,"unchanged callbacks do not rebuild observers")
                RunLoop.current.run(until:Date().addingTimeInterval(0.8))
                let reopened=try WorkspaceStore(directory:location)
                try expect(reopened.state.tabs.first?.title=="After" && reopened.state.tabs.first?.url=="https://example.com/new","pending metadata still commits")
            }),
            ("Repeated history visits do not emit empty transactions",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("visits-noop"));var notifications=0
                let observer=s.observe{notifications+=1};defer{s.removeObserver(observer)}
                s.recordVisit(title:"One",url:"https://example.com")
                for _ in 0..<100{s.recordVisit(title:"One",url:"https://example.com")}
                try expect(notifications==1 && s.state.history.count==1,"repeat visit has no observer side effects")
                s.recordVisit(title:"Two",url:"https://example.org")
                try expect(notifications==2 && s.state.history.count==2,"new visit remains durable and observable")
            }),
            ("Sleep protection rejects every unsafe lifecycle category",{
                try expect(TabSleepProtection(knownState:true).reason==nil,"known idle page eligible")
                let protected=[TabSleepProtection(loading:true,knownState:true),TabSleepProtection(playing:true,knownState:true),TabSleepProtection(capture:true,knownState:true),TabSleepProtection(upload:true,knownState:true),TabSleepProtection(download:true,knownState:true),TabSleepProtection(dirty:true,knownState:true),TabSleepProtection()]
                try expect(protected.allSatisfy{$0.reason != nil},"media, capture, transfer, dirty and unknown states stay protected")
            }),
            ("Continuous movement within a sidebar zone preserves the original dwell",{
                var intent=SidebarRevealIntent(),scheduled=0
                for _ in 0..<1000{if intent.transition(to:.reveal){scheduled+=1}}
                try expect(scheduled==1,"edge movement schedules one dwell")
                try expect(intent.transition(to:.none),"leaving cancels intent")
                try expect(intent.transition(to:.reveal),"re-entry starts a fresh dwell")
                try expect(intent.transition(to:.dismiss),"reversal changes target")
                for _ in 0..<1000{try expect(!intent.transition(to:.dismiss),"outside movement does not delay dismissal")}
                intent.reset();try expect(intent.zone == .none,"pin toggle can clear pending intent")
            }),
            ("Resource percentages normalize one core and reject resets or incomplete samples",{
                func sample(_ cpu:Double,_ count:Int=4,_ start:UInt64=9,_ at:Double)->ProcessResourceReading?{ProcessResourceReading(values:["complete":true,"cpuNanoseconds":cpu,"footprintBytes":NSNumber(value:100),"processCount":count,"rootStarted":NSNumber(value:start)],time:at)}
                let before=sample(1e9,4,9,10)!,after=sample(1.5e9,2,9,12)!
                try expect(after.cpuPercent(since:before)==25,"helper exit does not change CPU normalization")
                try expect(before.cpuPercent(since:nil)==nil,"first sample is measuring, not zero")
                try expect(sample(2e9,2,10,12)!.cpuPercent(since:before)==nil,"new browser identity resets baseline")
                try expect(sample(0.5e9,2,9,12)!.cpuPercent(since:before)==nil,"decreasing counter not shown as CPU")
                try expect(sample(.nan,2,9,12)==nil,"invalid counter rejected")
                try expect(ProcessResourceReading(values:["complete":false],time:12)==nil,"partial process list rejected")
            }),
            ("URL input preserves queries and blocks executable schemes",{
                try expect(Navigation.resolve("example.com/path")=="https://example.com/path","domain")
                try expect(Navigation.resolve("localhost:8765/test")=="http://localhost:8765/test","local port")
                try expect(Navigation.resolve("javascript:alert(1)")==nil,"javascript must not execute")
                try expect(Navigation.resolve("file:///etc/passwd")==nil,"file URL requires explicit file flow")
                let url=Navigation.resolve("a & b = c")!
                try expect(URLComponents(string:url)?.queryItems?.first?.value=="a & b = c","query encoding")
                try expect(Navigation.resolve("  ")==nil,"empty input")
                try expect(Navigation.displayHost("http://localhost:8765/page")=="localhost:8765","visible port")
            }),
            ("Committed workspace survives reopening",{
                let location=root.appendingPathComponent("persist")
                var s:WorkspaceStore?=try WorkspaceStore(directory:location)
                let id=s!.addTab(url:"https://example.com",pinned:true)
                let space=s!.addSpace(name:"Work")
                s!.moveTab(id,to:space)
                s!.flush();s=nil
                let reopened=try WorkspaceStore(directory:location)
                try expect(reopened.state.tabs.first?.id==id,"stable tab identity")
                try expect(reopened.state.tabs.first?.pinnedURL=="https://example.com","pin retained")
                try expect(reopened.state.activeSpace==space,"space retained")
            }),
            ("Committed organization survives abrupt process death with an open WAL",{
                for trial in 0..<3{
                    let location=root.appendingPathComponent("killed-writer-\(trial)"),child=Process()
                    child.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);child.arguments=["--crash-writer",location.path]
                    try child.run();defer{if child.isRunning{kill(child.processIdentifier,SIGKILL);child.waitUntilExit()}}
                    let expected=location.appendingPathComponent("expected-before-kill.json"),deadline=Date().addingTimeInterval(8)
                    while !FileManager.default.fileExists(atPath:expected.path) && child.isRunning && Date()<deadline{Thread.sleep(forTimeInterval:0.01)}
                    try expect(FileManager.default.fileExists(atPath:expected.path),"child committed before timeout")
                    try expect(FileManager.default.fileExists(atPath:location.appendingPathComponent("Workspace.sqlite-wal").path),"WAL remains open before process death")
                    kill(child.processIdentifier,SIGKILL);child.waitUntilExit()
                    try expect(child.terminationReason == .uncaughtSignal && child.terminationStatus==SIGKILL,"writer killed without graceful shutdown")
                    let state=try JSONDecoder().decode(VeilWorkspace.self,from:Data(contentsOf:expected)),reopened=try WorkspaceStore(directory:location)
                    try reopened.state.validate();try expect(reopened.state==state,"exact committed IDs, order, pins, folders, Spaces and archive recovered")
                }
            }),
            ("Onboarding pins in its own window Space and reuses an existing ordinary tab",{
                let store=try WorkspaceStore(directory:root.appendingPathComponent("onboarding-space")),first=store.state.activeSpace
                let tab=store.addTab(url:"https://www.apple.com/"),other=store.addSpace(name:"Other window")
                store.pinPracticeTab(in:first)
                try expect(store.state.activeSpace==other,"other window's persisted selection stays put")
                try expect(store.state.tabs.count==1 && store.state.tabs[0].id==tab && store.state.tabs[0].pinned,"existing ordinary tab becomes pin")
                store.pinPracticeTab(in:first);try expect(store.state.tabs.count==1,"practice is idempotent")
                store.pinPracticeTab(in:other);try expect(store.state.tabs.count==2 && store.state.tabs.last?.spaceID==other,"new pin belongs to originating window's Space")
                try expect(store.state.tabs.last?.lastUsed == .distantPast,"unopened practice pin stays out of recent tabs")
            }),
            ("Pinned close keeps the pin; explicit remove can undo",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("pin"))
                let id=s.addTab(url:"https://example.com",pinned:true)
                s.closeTab(id);try expect(s.state.tabs.count==1,"closing renderer must keep pin")
                s.closeTab(id,removePin:true);try expect(s.state.tabs.isEmpty,"explicit remove")
                s.undo();try expect(s.state.tabs.first?.id==id,"undo remove pin")
            }),
            ("Custom tab names survive webpage title changes and restart",{
                let path=root.appendingPathComponent("custom-title");var s:WorkspaceStore?=try WorkspaceStore(directory:path)
                let id=s!.addTab(url:"https://example.com",pinned:true);s!.change{$0.tabs[0].customTitle="My home"};s!.updateMetadata(tabID:id,title:"New webpage title");s!.flush();s=nil
                let reopened=try WorkspaceStore(directory:path);try expect(reopened.state.tabs[0].displayTitle=="My home","custom name retained")
                reopened.change{$0.tabs[0].customTitle=nil};try expect(reopened.state.tabs[0].displayTitle=="New webpage title","page title remains available")
            }),
            ("Space color and background persist without affecting another Space",{
                let path=root.appendingPathComponent("space-theme"),store=try WorkspaceStore(directory:path),first=store.state.activeSpace,other=store.addSpace(name:"Other")
                let theme=VeilSpaceAppearance(accentHex:"#B4A1E0",backgroundHex:"#20242A",style:"gradient",opacity:0.84)
                store.change{$0.spaces[0].appearance=theme};store.flush()
                let reopened=try WorkspaceStore(directory:path)
                try expect(reopened.state.spaces.first(where:{$0.id==first})?.appearance==theme,"exact theme restored")
                try expect(reopened.state.spaces.first(where:{$0.id==other})?.appearance==nil && reopened.state.activeSpace==other,"other Space and selection unchanged")
                store.undo();try expect(store.state.spaces[0].appearance==nil,"theme change undoes as one operation")
            }),
            ("Invalid theme colors and opacity roll back without corrupting storage",{
                let path=root.appendingPathComponent("invalid-theme"),store=try WorkspaceStore(directory:path),before=store.state
                for theme in [VeilSpaceAppearance(accentHex:"red"),VeilSpaceAppearance(backgroundHex:"#123"),VeilSpaceAppearance(style:"unknown"),VeilSpaceAppearance(opacity:0.1),VeilSpaceAppearance(opacity:.nan)]{
                    try expect(!store.change{$0.spaces[0].appearance=theme} && store.state==before,"invalid theme rejected atomically")
                }
                try expect(try WorkspaceStore(directory:path).state==before,"last valid workspace remains readable")
            }),
            ("Older Space data without appearance fields keeps its original identity",{
                var state=VeilWorkspace.fresh();state.spaces[0].appearance=VeilSpaceAppearance(accentHex:"#ABCDEF")
                var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(state)) as! [String:Any],spaces=object["spaces"] as! [[String:Any]]
                spaces[0].removeValue(forKey:"appearance");object["spaces"]=spaces
                let decoded=try JSONDecoder().decode(VeilWorkspace.self,from:JSONSerialization.data(withJSONObject:object))
                try expect(decoded.spaces[0].appearance==nil && decoded.spaces[0].id==state.spaces[0].id,"legacy Space uses system defaults with the same ID")
            }),
            ("Cross-Space moves preserve identity and exact order",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("move"))
                let a=s.addTab(url:"https://a.example"),b=s.addTab(url:"https://b.example")
                let target=s.addSpace(name:"Work")
                s.moveTab(a,to:target,before:b,pin:true)
                try expect(s.state.tabs.count==2,"move must not duplicate")
                try expect(s.state.tabs.map(\.id)==[a,b],"order")
                try expect(s.state.tabs[0].spaceID==target && s.state.tabs[0].pinned,"move and pin")
                s.undo();try expect(!s.state.tabs.first(where:{$0.id==a})!.pinned,"undo move")
            }),
            ("Invalid folder mutation rolls back atomically",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("rollback"))
                let id=s.addTab(url:"https://example.com"),before=s.state
                s.moveTab(id,to:s.state.activeSpace,folder:UUID())
                try expect(s.state==before,"invalid change rolled back in memory")
                let reopened=try WorkspaceStore(directory:root.appendingPathComponent("rollback"))
                try expect(reopened.state==before,"invalid change not persisted")
            }),
            ("Workspace validation refuses executable imported tab URLs",{
                var s=VeilWorkspace.fresh();s.tabs=[VeilTab(spaceID:s.activeSpace,title:"Bad",url:"javascript:alert(1)")]
                var rejected=false;do{try s.validate()}catch{rejected=true};try expect(rejected,"script URL rejected")
                s.tabs[0].url="https://example.com";s.tabs[0].pinnedURL="file:///etc/passwd";rejected=false;do{try s.validate()}catch{rejected=true};try expect(rejected,"unsafe reset pin rejected")
            }),
            ("Engine metadata cannot persist an unsupported internal URL",{
                let path=root.appendingPathComponent("metadata-url"),s=try WorkspaceStore(directory:path),id=s.addTab(url:"https://example.com")
                s.updateMetadata(tabID:id,title:"Failure",url:"chrome-error://chromewebdata/");s.flush();try s.state.validate()
                let reopened=try WorkspaceStore(directory:path);try expect(reopened.state.tabs[0].url=="https://example.com","last supported URL retained")
                reopened.updateMetadata(tabID:id,url:"javascript:alert(1)");reopened.flush();try reopened.state.validate()
            }),
            ("Folder cycles and excessive nesting are rejected",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("folders"))
                let a=s.addFolder(name:"Root"),b=s.addFolder(name:"Child",parent:a)
                let before=s.state
                let accepted=s.change{w in w.folders[0].parentID=b}
                try expect(!accepted && s.state==before,"cycle rejected")
                _=s.addFolder(name:"Too deep",parent:b)
                try expect(s.state.folders.count==2,"third level rejected")
            }),
            ("Folder moves transfer descendants and reject cycles atomically",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("folder-move"))
                let folder=s.addFolder(name:"Root"),child=s.addFolder(name:"Child",parent:folder),tab=s.addTab(url:"https://example.com",pinned:true)
                s.moveTab(tab,to:s.state.activeSpace,folder:child);let space=s.addSpace(name:"Other"),before=s.state
                try expect(!s.canMoveFolder(folder,to:space,parent:child),"cycle preview rejected")
                try expect(s.state==before,"preview doesn't mutate")
                try expect(s.moveFolder(folder,to:space),"subtree move accepted")
                try expect(s.state.tabs.first?.spaceID==space && s.state.folders.allSatisfy{$0.spaceID==space},"all descendants transferred")
                s.undo();try expect(s.state==before,"subtree move is one undo")
            }),
            ("Recently closed restores into a valid Space",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("archive"))
                let original=s.state.activeSpace,id=s.addTab(url:"https://example.com")
                s.closeTab(id);let target=s.addSpace(name:"New")
                s.deleteSpace(original,moveTo:target)
                try expect(s.reopenLast()==id,"reopen identity")
                try expect(s.state.tabs.first?.spaceID==target,"deleted Space fallback")
                try s.state.validate()
            }),
            ("Favorites are global within a profile",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("favorite"))
                let id=s.addTab(url:"https://example.com",favorite:true)
                _=s.addSpace(name:"Other")
                try expect(s.state.visibleTabs().map(\.id)==[id],"same Favorite in other Space")
                s.selectTab(id);try expect(s.state.spaces.count==2 && s.state.tabs.count==1,"no duplicate")
            }),
            ("Window selections stay independent while sharing organization",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("windows")),a=s.addTab(url:"https://a.example"),b=s.addTab(url:"https://b.example")
                var first=WindowSelection(s.state),second=WindowSelection(s.state)
                first.selectTab(s.state.tabs.first(where:{$0.id==a})!);s.selectTab(a)
                try expect(first.applying(to:s.state).space.lastTab==a,"first selection")
                try expect(second.applying(to:s.state).space.lastTab==b,"other window does not navigate")
                let space=s.addSpace(name:"Other");first.selectSpace(space,in:s.state);second.reconcile(s.state)
                try expect(first.applying(to:s.state).activeSpace==space && second.applying(to:s.state).activeSpace != space,"independent Spaces")
                second.clear();s.selectTab(a);try expect(second.applying(to:s.state).space.lastTab==nil,"explicit empty selection stays empty")
            }),
            ("Local tab presentation matches the actual window without changing persisted URLs",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("presentations")),id=s.addTab(url:"https://second.example/two",title:"Second page")
                let selection=WindowSelection(s.state),original=s.state
                let first=selection.applying(to:s.state,presentations:[id:.init(title:"Draft in first window",url:"https://first.example/form")])
                try expect(first.tabs[0].url=="https://first.example/form" && first.tabs[0].displayTitle=="Draft in first window","window presents its own page")
                try expect(first.visibleTabs().filter{$0.displayTitle.localizedStandardContains("Draft")}.map(\.id)==[id],"tab search can find the first window's actual title")
                try expect(s.state==original,"presentation doesn't navigate or persist another window")
                let invalid=selection.applying(to:s.state,presentations:[id:.init(title:nil,url:"chrome-error://chromewebdata/")])
                try expect(invalid.tabs[0].url==original.tabs[0].url,"internal error URL never replaces a real origin")
                s.change{$0.tabs[0].customTitle="My name"}
                try expect(selection.applying(to:s.state,presentations:[id:.init(title:"Page changed",url:nil)]).tabs[0].displayTitle=="My name","custom names win over page titles")
            }),
            ("Closing tabs releases cached objects while pending-close objects stay alive",{
                var cache=TabCache<CacheProbe>();let pending=UUID(),closed=UUID()
                weak var pendingReference:CacheProbe?,closedReference:CacheProbe?
                do{let one=CacheProbe(),two=CacheProbe();pendingReference=one;closedReference=two;cache[pending]=one;cache[closed]=two}
                cache.retain([pending]);try expect(closedReference==nil,"closed cache object released")
                try expect(pendingReference != nil && cache.count==1,"before-unload object retained until decision")
                cache.retain([]);try expect(pendingReference==nil && cache.count==0,"object released when close completes")
            }),
            ("Runtime cache retention stays bounded after many tab lifecycles",{
                var cache=TabCache<CacheProbe>();let active=UUID();cache[active]=CacheProbe()
                for _ in 0..<1000{let transient=UUID();cache[transient]=CacheProbe();cache.retain([active])}
                try expect(cache.count==1,"closed tabs cannot accumulate runtime image/record owners")
            }),
            ("Favicon origins separate sites without storing paths or credentials",{
                try expect(FaviconStore.origin("HTTPS://user:secret@EXAMPLE.com:443/private?q=one#two")=="https://example.com","canonical HTTPS origin")
                try expect(FaviconStore.origin("http://example.com:80/a")=="http://example.com","standard HTTP port omitted")
                try expect(FaviconStore.origin("https://example.com:8443/a")=="https://example.com:8443","nonstandard port retained")
                try expect(FaviconStore.origin("https://example.com") != FaviconStore.origin("http://example.com"),"schemes have separate icons")
                try expect(FaviconStore.origin("file:///private/file")==nil && FaviconStore.origin("javascript:alert(1)")==nil,"unsupported origins rejected")
            }),
            ("Favicon cache survives restart and private workspaces never persist images",{
                let png=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aLucAAAAASUVORK5CYII=")!
                let location=root.appendingPathComponent("favicon-persist"),url="https://user:secret@example.com/private-page?token=one"
                var store:WorkspaceStore?=try WorkspaceStore(directory:location)
                try expect(store!.favicons.save(png,for:url),"normal image saved");store=nil
                let reopened=try WorkspaceStore(directory:location)
                try expect(reopened.favicons.data(for:"https://example.com/another")==png,"same origin image restored before loading page")
                let folder=location.appendingPathComponent("Favicons"),files=try FileManager.default.contentsOfDirectory(atPath:folder.path)
                try expect(files.count==1 && files[0].range(of:"^[a-f0-9]{64}\\.png$",options:.regularExpression) != nil,"filename contains only origin hash")
                let mode=(try FileManager.default.attributesOfItem(atPath:folder.path)[.posixPermissions] as? NSNumber)?.intValue
                try expect(mode==0o700,"favicon directory private to owner")
                let privateLocation=root.appendingPathComponent("favicon-private"),privateStore=try WorkspaceStore(directory:privateLocation,privateMode:true)
                try expect(privateStore.favicons.save(png,for:url) && privateStore.favicons.data(for:url)==png,"private images usable in memory")
                try expect(!FileManager.default.fileExists(atPath:privateLocation.path),"private images leave no files")
                try expect(reopened.favicons.data(for:"https://other.example")==nil,"other sites don't inherit this image")
            }),
            ("Favicon cache bounds memory and disk without deleting unrelated files",{
                let png=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aLucAAAAASUVORK5CYII=")!
                let location=root.appendingPathComponent("favicon-limits");try FileManager.default.createDirectory(at:location,withIntermediateDirectories:true)
                let unrelated=location.appendingPathComponent("keep.txt");try Data("keep".utf8).write(to:unrelated)
                let cache=FaviconStore(directory:location,memoryLimit:3,diskLimit:2)
                for i in 0..<20{try expect(cache.save(png,for:"https://site\(i).example"),"image accepted");_=cache.data(for:"https://missing\(i).example")}
                try expect(cache.memoryEntryCount<=3,"positive and negative memory entries bounded together")
                let files=try FileManager.default.contentsOfDirectory(atPath:location.path)
                try expect(files.filter{$0.hasSuffix(".png")}.count==2,"disk entry bound retained")
                try expect(try Data(contentsOf:unrelated)==Data("keep".utf8),"unrelated file untouched")
                try expect(FaviconStore(directory:location).data(for:"https://site19.example")==png,"newest image survives trim")
            }),
            ("Favicon cache refuses oversized, malformed, and symlinked images",{
                let png=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aLucAAAAASUVORK5CYII=")!
                var hugeDimensions=png;hugeDimensions.replaceSubrange(16..<20,with:[0,0,2,0])
                let location=root.appendingPathComponent("favicon-invalid"),cache=FaviconStore(directory:location),url="https://example.com"
                try expect(!cache.save(hugeDimensions,for:url),"large decoded dimensions rejected")
                try expect(!cache.save(Data(repeating:0,count:FaviconStore.maximumBytes+1),for:url),"byte bound enforced")
                try expect(!cache.save(Data("not an image".utf8),for:url),"invalid header rejected")
                try expect(cache.save(png,for:url),"valid bounded image accepted")
                let file=try FileManager.default.contentsOfDirectory(at:location,includingPropertiesForKeys:nil).first!,target=root.appendingPathComponent("favicon-link-target.png")
                try png.write(to:target);try FileManager.default.removeItem(at:file);try FileManager.default.createSymbolicLink(at:file,withDestinationURL:target)
                try expect(FaviconStore(directory:location).data(for:url)==nil,"disk cache does not follow symlinks")
            }),
            ("Deleting Space transfers tabs and folders",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("delete"))
                let old=s.state.activeSpace,folder=s.addFolder(name:"Docs"),id=s.addTab(url:"https://example.com",pinned:true)
                s.moveTab(id,to:old,folder:folder)
                let target=s.addSpace(name:"Keep")
                s.deleteSpace(old,moveTo:target)
                try s.state.validate()
                try expect(s.state.tabs[0].spaceID==target && s.state.folders[0].spaceID==target,"both transferred")
            }),
            ("Private workspace leaves no files or history",{
                let path=root.appendingPathComponent("private")
                let s=try WorkspaceStore(directory:path,privateMode:true)
                _=s.addTab(url:"https://private.example")
                s.recordVisit(title:"Private",url:"https://private.example");s.flush()
                try expect(s.state.history.isEmpty,"private history")
                try expect(!FileManager.default.fileExists(atPath:path.path),"private metadata not on disk")
            }),
            ("Existing workspace directories become private to their owner",{
                let path=root.appendingPathComponent("permissions");try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true,attributes:[.posixPermissions:0o755])
                _=try WorkspaceStore(directory:path)
                let mode=(try FileManager.default.attributesOfItem(atPath:path.path)[.posixPermissions] as? NSNumber)?.intValue
                try expect(mode==0o700,"profile directory mode is 0700")
            }),
            ("Portable export omits history and downloads",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("export"))
                _=s.addTab(url:"https://example.com",pinned:true)
                s.recordVisit(title:"Private browsing context",url:"https://example.com")
                _=s.change{$0.downloads.append(VeilDownload(engineID:1,name:"personal.pdf",path:"/private/file.pdf"))}
                let path=root.appendingPathComponent("export.json");try s.export(to:path)
                let data=try JSONDecoder().decode(VeilWorkspace.self,from:Data(contentsOf:path))
                try expect(data.history.isEmpty && data.downloads.isEmpty,"sensitive metadata excluded")
                try expect(data.tabs.count==1,"tabs retained")
            }),
            ("Workspace import merges and remaps IDs",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("merge"))
                _=s.addTab(url:"https://example.com")
                let path=root.appendingPathComponent("merge.json");try s.export(to:path)
                try s.importWorkspace(from:path)
                try expect(s.state.tabs.count==2 && Set(s.state.tabs.map(\.id)).count==2,"tabs merged with new IDs")
                try expect(s.state.spaces.count==2,"spaces merged")
                try s.state.validate()
                s.undo();try expect(s.state.tabs.count==1,"import undo")
            }),
            ("Unreadable database is preserved instead of reset",{
                let path=root.appendingPathComponent("corrupt")
                try FileManager.default.createDirectory(at:path,withIntermediateDirectories:true)
                let db=path.appendingPathComponent("Workspace.sqlite"),original=Data("not a database".utf8)
                try original.write(to:db)
                var failed=false;do{_=try WorkspaceStore(directory:path)}catch{failed=true}
                try expect(failed,"corruption reported")
                try expect(try Data(contentsOf:db)==original,"original preserved")
            }),
            ("100-tab operation sequence preserves invariants",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("stress"))
                let ids=(0..<100).map{s.addTab(url:"https://example.com/\($0)")}
                let spaces=(0..<5).map{s.addSpace(name:"Space \($0)")}
                for (i,id) in ids.enumerated(){s.moveTab(id,to:spaces[i%5],pin:i%3==0)}
                for i in 0..<20{s.closeTab(ids[i],removePin:true)}
                for _ in 0..<10{_=s.reopenLast()}
                try s.state.validate()
                try expect(s.state.tabs.count==90,"no tabs lost beyond explicit closes")
                let reopened=try WorkspaceStore(directory:root.appendingPathComponent("stress"))
                try expect(reopened.state==s.state,"stress state persisted exactly")
            }),
            ("Bookmark import ignores executable URLs and decodes titles",{
                let html="""
                <DL><A HREF="https://example.com/?a=1&amp;b=2">A &amp; B &#x1F30D;</A>
                <a href='javascript:alert(1)'>Bad</a><a href=file:///etc/passwd>File</a>
                <a HREF=https://swift.org>Swift <b>Language</b></a></DL>
                """
                let items=try WorkspaceImport.parseHTML(html)
                try expect(items.count==2,"unsupported schemes rejected")
                try expect(items[0].title=="A & B 🌍" && items[0].url=="https://example.com/?a=1&b=2","entities decoded")
                try expect(items[1].title=="Swift Language","title markup stripped")
            }),
            ("Bookmark preview deduplicates, imports atomically, and undoes",{
                let s=try WorkspaceStore(directory:root.appendingPathComponent("bookmarks"))
                _=s.addTab(url:"https://EXAMPLE.com")
                let file=root.appendingPathComponent("bookmarks.html")
                try Data("<a href='https://example.com/'>Existing</a><a href='https://swift.org'>New</a><a href='https://swift.org/'>Duplicate</a>".utf8).write(to:file)
                let before=s.state,plan=try WorkspaceImport.preview(url:file,existing:s.state)
                try expect(plan.count==1,"canonical duplicate skip")
                try expect(s.state==before,"preview is read only")
                try WorkspaceImport.apply(plan,to:s);try s.state.validate()
                try expect(s.state.tabs.count==2 && s.state.folders.count==1,"one pin in imported folder")
                s.undo();try expect(s.state==before,"whole import undoes once")
            }),
            ("Interrupted downloads become retryable after restart",{
                let location=root.appendingPathComponent("interrupted")
                var s:WorkspaceStore?=try WorkspaceStore(directory:location)
                s!.change{$0.downloads.append(VeilDownload(engineID:4,sourceURL:"https://example.com/file",name:"Partial",path:"/private/tmp/partial",percent:42))};s=nil
                let reopened=try WorkspaceStore(directory:location),record=reopened.state.downloads[0]
                try expect(record.interrupted==true && record.cancelled && record.percent==42,"interruption preserved with retry URL")
            }),
            ("Backup recovery preserves original database and reopens exact state",{
                let location=root.appendingPathComponent("recovery")
                var s:WorkspaceStore?=try WorkspaceStore(directory:location)
                _=s!.addTab(url:"https://example.com",pinned:true);let expected=s!.state;s=nil
                let database=location.appendingPathComponent("Workspace.sqlite"),original=Data("synthetic corrupt database".utf8);try original.write(to:database)
                let recovered=try WorkspaceRecovery.openBackupCopy(location)
                try expect(recovered.state==expected,"exact IDs and pins restored")
                try expect(try Data(contentsOf:database)==original,"original never replaced")
                let next=try WorkspaceRecovery.open(location);try expect(next.state==expected,"recovery choice persists")
            }),
            ("Incompatible backup is refused without replacing data",{
                let location=root.appendingPathComponent("bad-backup");try FileManager.default.createDirectory(at:location,withIntermediateDirectories:true)
                let backup=location.appendingPathComponent("Workspace.backup.json"),original=Data("{\"version\":999}".utf8);try original.write(to:backup)
                var failed=false;do{_=try WorkspaceRecovery.openBackupCopy(location)}catch{failed=true}
                try expect(failed,"invalid backup rejected");try expect(try Data(contentsOf:backup)==original,"backup untouched")
                try expect(!FileManager.default.fileExists(atPath:location.appendingPathComponent("Workspace.recovery-location").path),"no marker on failure")
            }),
            ("Older workspace without optional onboarding fields remains readable",{
                let state=VeilWorkspace.fresh(),data=try JSONEncoder().encode(state)
                var object=try JSONSerialization.jsonObject(with:data) as! [String:Any];object.removeValue(forKey:"onboardingStep")
                let decoded=try JSONDecoder().decode(VeilWorkspace.self,from:JSONSerialization.data(withJSONObject:object))
                try expect(decoded==state,"optional field migration")
            })
        ]
        var failed=0
        for (name,body) in cases {
            do{try body();results.append(["name":name,"passed":true]);print("PASS \(name)")}
            catch{failed+=1;results.append(["name":name,"passed":false,"error":"\(error)"]);print("FAIL \(name): \(error)")}
        }
        let data=try JSONSerialization.data(withJSONObject:["passed":cases.count-failed,"failed":failed,"results":results],options:[.prettyPrinted,.sortedKeys])
        try data.write(to:root.deletingLastPathComponent().appendingPathComponent("workspace-tests.json"),options:.atomic)
        if failed>0{exit(1)}
    }
}
