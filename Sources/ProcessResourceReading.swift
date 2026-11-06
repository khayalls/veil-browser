import Foundation

struct ProcessResourceReading {
    let cpuNanoseconds:Double
    let footprintBytes:UInt64
    let processCount:Int
    let rootStarted:UInt64
    let time:TimeInterval
    init?(values:[String:Any],time:TimeInterval){
        guard values["complete"] as? Bool == true,
              let cpu=values["cpuNanoseconds"] as? Double,cpu.isFinite,cpu>=0,
              let memory=values["footprintBytes"] as? NSNumber,memory.doubleValue.isFinite,memory.doubleValue>=0,
              let count=values["processCount"] as? Int,count>0,
              let started=values["rootStarted"] as? NSNumber,time.isFinite else{return nil}
        cpuNanoseconds=cpu;footprintBytes=memory.uint64Value;processCount=count;rootStarted=started.uint64Value;self.time=time
    }
    func cpuPercent(since previous:ProcessResourceReading?)->Double?{
        guard let previous,rootStarted==previous.rootStarted,time>previous.time,cpuNanoseconds>=previous.cpuNanoseconds else{return nil}
        return 100*(cpuNanoseconds-previous.cpuNanoseconds)/1_000_000_000/(time-previous.time)
    }
}
