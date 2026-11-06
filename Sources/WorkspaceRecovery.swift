import Foundation

enum WorkspaceRecovery{
    static func activeDirectory(_ directory:URL)throws->URL{
        let marker=directory.appendingPathComponent("Workspace.recovery-location")
        guard FileManager.default.fileExists(atPath:marker.path) else{return directory}
        let value=try String(contentsOf:marker,encoding:.utf8)
        guard value.range(of:"^Recovery-[0-9A-F-]{36}$",options:.regularExpression) != nil else{throw WorkspaceError.invalid("Invalid recovery location. Original files are preserved.")}
        let result=directory.appendingPathComponent(value)
        guard result.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path+"/") else{throw WorkspaceError.invalid("Recovery location is outside this profile.")}
        return result
    }
    static func open(_ directory:URL)throws->WorkspaceStore{try WorkspaceStore(directory:activeDirectory(directory))}
    static func openBackupCopy(_ directory:URL)throws->WorkspaceStore{
        let source=try activeDirectory(directory),backup=source.appendingPathComponent("Workspace.backup.json")
        let data=try Data(contentsOf:backup);guard data.count<=20_000_000 else{throw WorkspaceError.invalid("Backup is too large to recover safely.")}
        let snapshot=try JSONDecoder().decode(VeilWorkspace.self,from:data);try snapshot.validate()
        let name="Recovery-"+UUID().uuidString
        let recovered=try WorkspaceStore(directory:directory.appendingPathComponent(name),initialState:snapshot)
        try Data(name.utf8).write(to:directory.appendingPathComponent("Workspace.recovery-location"),options:.atomic)
        return recovered
    }
}
