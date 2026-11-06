import Foundation
import CryptoKit

/// Small, disposable per-origin image cache. Private workspaces pass nil and
/// never write to disk. Filenames contain neither URLs nor browsing paths.
final class FaviconStore{
    static let maximumBytes=131_072
    private let directory:URL?
    private let memoryLimit:Int,diskLimit:Int
    private var memory:[String:Data]=[:],missing=Set<String>(),order:[String]=[]
    private var lastWrite:[String:Date]=[:]
    init(directory:URL?,memoryLimit:Int=128,diskLimit:Int=256){self.directory=directory;self.memoryLimit=max(1,memoryLimit);self.diskLimit=max(1,diskLimit)}
    var memoryEntryCount:Int{order.count}
    static func origin(_ address:String)->String?{
        guard let url=URLComponents(string:address),let scheme=url.scheme?.lowercased(),["http","https"].contains(scheme),let host=url.host?.lowercased(),!host.isEmpty else{return nil}
        let port=url.port;let suffix=port.flatMap{($0==80 && scheme=="http") || ($0==443 && scheme=="https") ? nil:":\($0)"} ?? ""
        return scheme+"://"+host+suffix
    }
    private static func key(_ address:String)->String?{origin(address).map{SHA256.hash(data:Data($0.utf8)).map{String(format:"%02x",$0)}.joined()}}
    static func accepts(_ data:Data)->Bool{
        guard data.count>=24,data.count<=maximumBytes else{return false};let b=Array(data.prefix(24))
        guard Array(b[0..<8])==[137,80,78,71,13,10,26,10],Array(b[12..<16])==[73,72,68,82] else{return false}
        func number(_ offset:Int)->UInt32{(offset..<offset+4).reduce(UInt32(0)){($0<<8)|UInt32(b[$1])}}
        return (1...256).contains(number(16)) && (1...256).contains(number(20))
    }
    private func touch(_ key:String){order.removeAll{$0==key};order.append(key);while order.count>memoryLimit{let old=order.removeFirst();memory[old]=nil;missing.remove(old);lastWrite[old]=nil}}
    func data(for address:String)->Data?{
        guard let key=Self.key(address) else{return nil}
        if let data=memory[key]{touch(key);return data};if missing.contains(key){touch(key);return nil}
        defer{touch(key)}
        guard let directory else{missing.insert(key);return nil}
        let file=directory.appendingPathComponent(key+".png")
        guard let values=try? file.resourceValues(forKeys:[.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey]),values.isRegularFile==true,values.isSymbolicLink != true,(values.fileSize ?? Int.max)<=Self.maximumBytes,let data=try? Data(contentsOf:file),Self.accepts(data) else{missing.insert(key);return nil}
        memory[key]=data;return data
    }
    @discardableResult func save(_ data:Data,for address:String)->Bool{
        guard Self.accepts(data),let key=Self.key(address) else{return false}
        if memory[key]==data{touch(key);return true}
        memory[key]=data;missing.remove(key);touch(key)
        guard let directory else{return true}
        // Animated favicons may change often; keep their latest image in RAM
        // without continuously writing a browsing session to disk.
        if let last=lastWrite[key],Date().timeIntervalSince(last)<30{return true}
        do{
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
            try data.write(to:directory.appendingPathComponent(key+".png"),options:.atomic);lastWrite[key]=Date();trimDisk(directory)
        }catch{/* Cache failure never prevents browsing or workspace saves. */}
        return true
    }
    private func trimDisk(_ directory:URL){
        let files=((try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.contentModificationDateKey],options:.skipsHiddenFiles)) ?? []).filter{$0.lastPathComponent.range(of:"^[a-f0-9]{64}\\.png$",options:.regularExpression) != nil}
        guard files.count>diskLimit else{return}
        let sorted=files.sorted{((try? $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate) ?? .distantPast)}
        for file in sorted.prefix(files.count-diskLimit){try? FileManager.default.removeItem(at:file)}
    }
}
