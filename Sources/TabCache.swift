import Foundation

/// Retain metadata for stored tabs and for engines still negotiating close.
/// Archived/deleted tabs must not keep images and runtime objects alive.
struct TabCache<Value>:Sequence{
    private var storage:[UUID:Value]=[:]
    var count:Int{storage.count}
    subscript(id:UUID)->Value?{get{storage[id]}set{storage[id]=newValue}}
    mutating func retain(_ ids:Set<UUID>){storage=storage.filter{ids.contains($0.key)}}
    func makeIterator()->Dictionary<UUID,Value>.Iterator{storage.makeIterator()}
}
