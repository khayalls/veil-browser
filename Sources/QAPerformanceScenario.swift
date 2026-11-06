import AppKit

/// Explicit synthetic QA only. Exercises real native controls and CEF fixtures;
/// it does not stand in for physical trackpad or user input latency testing.
final class QAPerformanceScenario {
    private weak var browser:BrowserWindowController?
    private let directory=URL(fileURLWithPath:VEProfileRoot())
    private var blank:UUID?,clean:UUID?,dirty:UUID?,media:UUID?
    private var checks:[String]=[],finished=false
    private weak var panel:NSWindow?
    init(browser:BrowserWindowController){self.browser=browser}
    private func later(_ seconds:Double=0.15,_ block:@escaping()->Void){DispatchQueue.main.asyncAfter(deadline:.now()+seconds,execute:block)}
    private func report(_ phase:String,_ error:String?=nil){
        var value:[String:Any]=["phase":phase,"checks":checks,"method":"App-owned native NSControl dispatch, actual CEF loopback fixtures, AppKit view raster and on-demand resource counters","profileBuild":directory.lastPathComponent,"date":ISO8601DateFormatter().string(from:Date())]
        if let error{value["error"]=error}
        if let data=try? JSONSerialization.data(withJSONObject:value,options:.prettyPrinted){try? data.write(to:directory.appendingPathComponent("qa-performance-scenario.json"),options:.atomic)}
    }
    private func fail(_ message:String){finished=true;report("failed",message)}
    private func wait(_ remaining:Int=200,for test:@escaping()->Bool,then next:@escaping()->Void){
        guard !finished else{return};if test(){next()}else if remaining>0{later{[weak self] in self?.wait(remaining-1,for:test,then:next)}}else{fail("Timed out waiting for the current native/fixture state.")}
    }
    func start(){
        guard ProcessInfo.processInfo.arguments.contains("--veil-qa"),let browser,browser.store.state.tabs.count<=1 else{fail("Requires a fresh synthetic QA profile.");return}
        blank=browser.store.state.tabs.first?.id ?? browser.openURL("about:blank");report("loading")
        load("http://127.0.0.1:8765/page/performance"){[weak self] id in self?.clean=id;self?.load("http://127.0.0.1:8765/form"){[weak self] id in self?.dirty=id;self?.load("http://127.0.0.1:8765/media"){[weak self] id in self?.media=id;self?.prepareProtection()}}}
    }
    private func load(_ url:String,_ next:@escaping(UUID)->Void){guard let browser else{return};let id=browser.openURL(url);wait(for:{[weak browser] in browser?.qaIsSettled(id)==true},then:{next(id)})}
    private func prepareProtection(){
        guard let browser,let dirty,let media,let blank else{return}
        browser.qaScript(dirty,"document.getElementById('draft').value='Synthetic VEIL resource test';document.getElementById('draft').dispatchEvent(new Event('input',{bubbles:true}));")
        browser.qaScript(media,"const a=document.getElementById('audio');a.muted=true;a.play().catch(()=>{});")
        browser.selectTab(blank)
        wait(for:{[weak browser] in let rows=browser?.performanceTabs() ?? [];return rows.first(where:{$0.id==dirty})?.activity=="Unsaved changes" && rows.first(where:{$0.id==media})?.activity=="Playing"},then:{[weak self] in self?.openPanel()})
    }
    private func table()->NSTableView?{panel?.contentView?.flatSubviews().compactMap{$0 as? NSTableView}.first}
    private func control(_ id:UUID,column:Int)->NSControl?{guard let browser,let row=browser.performanceTabs().firstIndex(where:{$0.id==id}) else{return nil};return table()?.view(atColumn:column,row:row,makeIfNecessary:true) as? NSControl}
    private func openPanel(){
        guard let browser,let blank,let clean,let dirty,let media else{return};browser.execute("performance");panel=NSApp.keyWindow
        guard panel?.title=="Performance",let table=table() else{fail("Performance did not open a native table window.");return}
        panel?.contentView?.layoutSubtreeIfNeeded();table.layoutSubtreeIfNeeded()
        guard control(blank,column:3)?.isEnabled==false,control(dirty,column:3)?.isEnabled==false,control(media,column:3)?.isEnabled==false,let keep=control(clean,column:2) as? NSButton else{fail("Active, dirty or media protection is missing from the controls.");return}
        checks.append("Native Sleep controls disable active, dirty and playing tabs")
        keep.performClick(nil)
        guard browser.store.state.tabs.first(where:{$0.id==clean})?.keepAwake==true,control(clean,column:3)?.isEnabled==false else{fail("Keep Awake toggle did not protect the tab.");return}
        checks.append("Native Keep Awake toggle persists and disables Sleep")
        guard let reset=control(clean,column:2) as? NSButton else{fail("Keep Awake control disappeared.");return};reset.performClick(nil)
        guard let sleep=control(clean,column:3) as? NSButton,sleep.isEnabled else{fail("Idle unprotected tab cannot sleep.");return};sleep.performClick(nil)
        wait(for:{[weak browser] in browser?.isSleeping(clean)==true},then:{[weak self] in self?.measureAndCapture()})
    }
    private func measureAndCapture(){
        guard let browser,let clean else{return};guard browser.store.state.tabs.contains(where:{$0.id==clean}) else{fail("Sleep removed the durable tab record.");return}
        checks.append("Native Sleep tears down the real CEF engine and keeps its tab identity")
        let metrics=directory.appendingPathComponent("qa-performance.json")
        wait(for:{guard let data=try? Data(contentsOf:metrics),let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{return false};return value["cpuPercent"] is NSNumber && ((value["footprintBytes"] as? NSNumber)?.uint64Value ?? 0)>0},then:{[weak self] in self?.captureAndClose()})
    }
    private func captureAndClose(){
        guard let panel,let view=panel.contentView else{fail("Native resource window closed before capture.");return}
        checks.append("Visible CPU and approximate process-memory readings are available")
        view.layoutSubtreeIfNeeded();view.displayIfNeeded()
        guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{fail("Native view raster unavailable.");return}
        view.cacheDisplay(in:view.bounds,to:bitmap)
        guard let image=bitmap.representation(using:.png,properties:[:]) else{fail("Native view raster encoding failed.");return}
        do{try image.write(to:directory.appendingPathComponent("qa-performance.png"),options:.atomic)}catch{fail("Unable to save the synthetic UI capture.");return}
        checks.append("Native Performance view raster captured")
        panel.performClose(nil)
        later(0.4){[weak self] in
            guard let self else{return};let file=self.directory.appendingPathComponent("qa-performance.json"),before=try? Data(contentsOf:file)
            self.later(4.5){[weak self] in guard let self else{return};if before != (try? Data(contentsOf:file)){self.fail("Resource sampler kept updating after the window closed.");return};self.checks.append("Closing the native window stops resource sampling");self.finish()}
        }
    }
    private func finish(){
        guard let browser else{return}
        if let dirty{browser.qaScript(dirty,"document.getElementById('save').click();")}
        if let media{browser.qaScript(media,"document.getElementById('audio').pause();")}
        later(0.4){[weak self] in guard let self,let browser=self.browser else{return};for id in [self.clean,self.dirty,self.media].compactMap({$0}){browser.closeTab(id)};self.wait(for:{[weak browser] in browser?.store.state.tabs.count==1},then:{[weak self] in guard let self else{return};self.finished=true;self.report("complete")})}
    }
}
private extension NSView {
    func flatSubviews()->[NSView]{subviews.flatMap{[$0]+$0.flatSubviews()}}
}
