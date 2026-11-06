import Foundation

struct ImportedBookmark:Equatable{let title:String,url:String}
enum WorkspaceImportPlan{
    case workspace(VeilWorkspace,URL)
    case bookmarks([ImportedBookmark],duplicates:Int)
    var summary:String{switch self{case .workspace(let state,_):return "\(state.spaces.count) Spaces, \(state.tabs.count) tabs, and \(state.folders.count) folders. Existing items stay in place.";case .bookmarks(let items,let duplicates):return "\(items.count) new bookmarks. \(duplicates) duplicates skipped. Only http and https links are supported. New bookmarks will be pinned in an Imported Bookmarks folder."}}
    var count:Int{switch self{case .workspace(let state,_):return state.tabs.count;case .bookmarks(let items,_):return items.count}}
}
enum WorkspaceImport{
    static func preview(url:URL,existing:VeilWorkspace)throws->WorkspaceImportPlan{
        let data=try Data(contentsOf:url,options:.mappedIfSafe)
        guard data.count<=10_000_000 else{throw WorkspaceError.invalid("Choose a bookmark or workspace file smaller than 10 MB.")}
        if url.pathExtension.lowercased()=="json"{
            let state=try JSONDecoder().decode(VeilWorkspace.self,from:data);try state.validate();return .workspace(state,url)
        }
        guard let html=String(data:data,encoding:.utf8) ?? String(data:data,encoding:.utf16) else{throw WorkspaceError.invalid("That bookmark file couldn't be read.")}
        let parsed=try parseHTML(html)
        var seen=Set(existing.tabs.map{Navigation.canonicalURL($0.url)}),items:[ImportedBookmark]=[]
        var skipped=0
        for bookmark in parsed{
            let key=Navigation.canonicalURL(bookmark.url)
            if seen.contains(key){skipped+=1}else{seen.insert(key);items.append(bookmark)}
        }
        guard !parsed.isEmpty else{throw WorkspaceError.invalid("No supported http or https bookmarks were found.")}
        return .bookmarks(items,duplicates:skipped)
    }
    static func apply(_ plan:WorkspaceImportPlan,to store:WorkspaceStore)throws{
        switch plan{
        case .workspace(_,let url):try store.importWorkspace(from:url)
        case .bookmarks(let items,_):
            guard !items.isEmpty else{return}
            let folder=VeilFolder(spaceID:store.state.activeSpace,name:"Imported Bookmarks")
            guard store.change({state in
                state.folders.append(folder)
                state.tabs.append(contentsOf:items.map{item in VeilTab(spaceID:state.activeSpace,folderID:folder.id,title:item.title,url:item.url,pinnedURL:item.url,lastUsed:.distantPast)})
            }) else{throw WorkspaceError.storage("The import couldn't be saved. Your existing tabs are unchanged.")}
        }
    }
    static func parseHTML(_ html:String)throws->[ImportedBookmark]{
        guard html.utf8.count<=10_000_000 else{throw WorkspaceError.invalid("That bookmark file is too large.")}
        // Parse link tokens only. No HTML renderer, scripts, external resources,
        // XML entities or network access are involved in bookmark import.
        let expression=try NSRegularExpression(pattern:#"<a\b[^>]*\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))[^>]*>(.*?)</a\s*>"#,options:[.caseInsensitive,.dotMatchesLineSeparators])
        let source=html as NSString
        var bookmarks:[ImportedBookmark]=[]
        for match in expression.matches(in:html,range:NSRange(location:0,length:source.length)).prefix(10_000){
            guard let range=(1...3).map({match.range(at:$0)}).first(where:{$0.location != NSNotFound}) else{continue}
            let address=entities(source.substring(with:range)).trimmingCharacters(in:.whitespacesAndNewlines)
            guard address.count<=16384,let url=URL(string:address),["http","https"].contains(url.scheme?.lowercased() ?? ""),url.host != nil else{continue}
            let text=source.substring(with:match.range(at:4)).replacingOccurrences(of:"<[^>]*>",with:"",options:.regularExpression)
            let title=String(entities(text).trimmingCharacters(in:.whitespacesAndNewlines).prefix(512))
            bookmarks.append(.init(title:title.isEmpty ? Navigation.displayHost(url.absoluteString):title,url:url.absoluteString))
        }
        return bookmarks
    }
    private static func entities(_ value:String)->String{
        var result=value
        let expression=try! NSRegularExpression(pattern:#"&#(x[0-9a-fA-F]+|[0-9]+);"#)
        for match in expression.matches(in:result,range:NSRange(location:0,length:(result as NSString).length)).reversed(){
            let raw=(result as NSString).substring(with:match.range(at:1));let number=raw.hasPrefix("x") ? UInt32(raw.dropFirst(),radix:16):UInt32(raw)
            if let number,let scalar=UnicodeScalar(number){result=(result as NSString).replacingCharacters(in:match.range,with:String(scalar))}
        }
        for (entity,plain) in [("&quot;","\""),("&apos;","'"),("&lt;","<"),("&gt;",">"),("&nbsp;"," "),("&amp;","&")]{result=result.replacingOccurrences(of:entity,with:plain)}
        return result
    }
}
