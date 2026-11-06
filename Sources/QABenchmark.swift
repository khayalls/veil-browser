import AppKit

/// Explicit --veil-qa --veil-benchmark only. Uses disposable local fixtures;
/// never runs in a normal profile and never logs webpage contents.
final class QABenchmark{
    private weak var browser:BrowserWindowController?
    private let directory=URL(fileURLWithPath:VEProfileRoot())
    private var tabs:[UUID]=[]
    private var trial=1
    private var timings:[String:[Double]]=[:]
    init(browser:BrowserWindowController){self.browser=browser}
    private func later(_ seconds:Double=0.1,_ body:@escaping()->Void){DispatchQueue.main.asyncAfter(deadline:.now()+seconds,execute:body)}
    private func publish(_ phase:String,extra:[String:Any]=[:]){
        var object=extra;object["phase"]=phase;object["trial"]=trial;object["pid"]=ProcessInfo.processInfo.processIdentifier;object["date"]=ISO8601DateFormatter().string(from:Date())
        if let data=try? JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]){try? data.write(to:directory.appendingPathComponent("qa-phase.json"),options:.atomic)}
    }
    private func awaitContinue(_ phase:String,_ next:@escaping()->Void){
        let file=directory.appendingPathComponent("continue-\(trial)-\(phase)")
        if FileManager.default.fileExists(atPath:file.path){try? FileManager.default.removeItem(at:file);next()}else{later(0.25){[weak self] in self?.awaitContinue(phase,next)}}
    }
    func start(){
        guard ProcessInfo.processInfo.arguments.contains("--veil-qa"),let browser,browser.store.state.tabs.isEmpty else{publish("error",extra:["message":"Benchmark requires a fresh QA profile."]);return}
        let blank=browser.openURL("about:blank")
        waitForTab(blank){[weak self] in self?.later(60){self?.emptyReady()}}
    }
    private func emptyReady(){publish("empty");awaitContinue("empty"){[weak self] in self?.prepareTabs()}}
    private func prepareTabs(){
        guard let browser else{return}
        if tabs.isEmpty{
            let spaces=(0..<5).map{VeilSpace(name:"QA Space \($0+1)",color:$0)}
            let records=(0..<30).map{VeilTab(spaceID:spaces[$0%5].id,title:"Fixture \($0+1)",url:"http://127.0.0.1:8765/bench/\($0+1)")};tabs=records.map(\.id)
            browser.store.change{s in s.spaces=spaces;s.activeSpace=spaces[0].id;s.tabs=records;s.history=[];s.archive=[];s.folders=[]}
        }
        loadNext(0)
    }
    private func waitForTab(_ id:UUID,remaining:Int=200,_ next:@escaping()->Void){
        guard let browser else{return}
        if browser.qaIsSettled(id){later(0.1,next)}else if remaining>0{later(0.1){[weak self] in self?.waitForTab(id,remaining:remaining-1,next)}}else{publish("error",extra:["message":"Fixture did not settle.","tab":id.uuidString])}
    }
    private func loadNext(_ index:Int){
        guard let browser else{return}
        guard tabs.indices.contains(index) else{later(60){[weak self] in guard let self else{return};self.publish("all-live",extra:["live":browser.qaLiveCount]);self.awaitContinue("all-live"){self.sleepTabs()}};return}
        browser.selectTab(tabs[index]);waitForTab(tabs[index]){[weak self] in self?.loadNext(index+1)}
    }
    private func sleepTabs(){
        guard let browser else{return};for tab in tabs.prefix(25){browser.qaSleep(tab)}
        awaitSleep(remaining:200)
    }
    private func awaitSleep(remaining:Int){
        guard let browser else{return}
        if browser.qaLiveCount==5{later(60){[weak self] in guard let self else{return};self.publish("unloaded",extra:["live":browser.qaLiveCount]);self.awaitContinue("unloaded"){self.nextTrial()}}}
        else if remaining>0{later(0.1){[weak self] in self?.awaitSleep(remaining:remaining-1)}}else{publish("error",extra:["message":"Protected tabs did not unload.","live":browser.qaLiveCount])}
    }
    private func nextTrial(){if trial<3{trial+=1;prepareTabs()}else{measure(0)}}
    private func measure(_ index:Int){
        guard let browser else{return}
        if index>=100{publish("complete",extra:["timings_ms":timings,"metric_boundary":"Native synchronous action plus NSWindow.displayIfNeeded; excludes compositor presentation and webpage loading."]);return}
        let start=ProcessInfo.processInfo.systemUptime
        browser.selectTab(tabs[25+index%5]);browser.window?.displayIfNeeded()
        timings["tab_space_switch",default:[]].append((ProcessInfo.processInfo.systemUptime-start)*1000)
        let commandStart=ProcessInfo.processInfo.systemUptime
        browser.showCommandBar();browser.window?.displayIfNeeded();browser.qaDismissCommand()
        timings["command_overlay",default:[]].append((ProcessInfo.processInfo.systemUptime-commandStart)*1000)
        later(0.05){[weak self] in self?.measure(index+1)}
    }
}
