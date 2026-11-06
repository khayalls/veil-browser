import Foundation

struct WindowTabPresentation:Equatable{
    var title:String?
    var url:String?
}

/// Window focus is local; tab organization and the last persisted session are
/// shared. A selection in one window must not navigate another window.
struct WindowSelection{
    private(set) var activeSpace:UUID
    private var selected:[UUID:UUID?]
    init(_ state:VeilWorkspace){activeSpace=state.activeSpace;selected=Dictionary(uniqueKeysWithValues:state.spaces.map{($0.id,$0.lastTab)})}
    mutating func selectSpace(_ id:UUID,in state:VeilWorkspace){guard let space=state.spaces.first(where:{$0.id==id}) else{return};activeSpace=id;if selected[id]==nil{selected.updateValue(space.lastTab,forKey:id)}}
    mutating func selectTab(_ tab:VeilTab){if !tab.favorite{activeSpace=tab.spaceID};selected.updateValue(tab.id,forKey:activeSpace)}
    mutating func clear(){selected.updateValue(nil,forKey:activeSpace)}
    mutating func reconcile(_ state:VeilWorkspace){if !state.spaces.contains(where:{$0.id==activeSpace}){activeSpace=state.activeSpace};selected=selected.filter{key,_ in state.spaces.contains(where:{$0.id==key})}}
    func selectedTabID(in state:VeilWorkspace)->UUID?{
        guard let space=state.spaces.first(where:{$0.id==activeSpace}) else{return nil}
        let candidate:UUID?;if let local=selected[activeSpace]{candidate=local}else{candidate=space.lastTab}
        guard let candidate,state.tabs.contains(where:{$0.id==candidate && ($0.favorite || $0.spaceID==activeSpace)}) else{return nil}
        return candidate
    }
    func applying(to state:VeilWorkspace,presentations:[UUID:WindowTabPresentation]=[:])->VeilWorkspace{
        var copy=state;copy.activeSpace=activeSpace
        for i in copy.spaces.indices{if let value=selected[copy.spaces[i].id]{copy.spaces[i].lastTab=value};if let id=copy.spaces[i].lastTab,!copy.tabs.contains(where:{$0.id==id && ($0.favorite || $0.spaceID==copy.spaces[i].id)}){copy.spaces[i].lastTab=nil}}
        for i in copy.tabs.indices{if let local=presentations[copy.tabs[i].id]{if let title=local.title,!title.isEmpty{copy.tabs[i].title=title};if let url=local.url,Navigation.isSupportedURL(url){copy.tabs[i].url=url}}}
        return copy
    }
}
