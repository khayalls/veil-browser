import AppKit

final class MediaCard:FlippedView{
    private let material=GlassSurface(radius:22)
    private let title=veilLabel("Media",size:12,weight:.semibold),artist=veilLabel("",size:10,color:.secondaryLabelColor)
    private var controls:[String:ActionButton]=[:]
    var onAction:((String)->Void)?
    override init(frame:NSRect){
        super.init(frame:frame)
        addSubview(material);material.content.addSubview(title);material.content.addSubview(artist)
        for (id,icon,help) in [("previoustrack","skip-back","Previous track"),("toggle","play","Play or pause"),("nexttrack","skip-forward","Next track"),("mute","speaker-high","Mute or unmute"),("source","arrow-square-out","Go to media tab"),("dismiss","x","Hide media controls")]{
            let button=ActionButton(icon:icon,help:help){ [weak self] in self?.onAction?(id) };controls[id]=button;material.content.addSubview(button)
            button.setAccessibilityIdentifier("veil.media.\(id)")
        }
        setAccessibilityIdentifier("veil.media.controller");isHidden=true
    }
    required init?(coder:NSCoder){fatalError()}
    func update(title:String,artist:String,playing:Bool,previous:Bool,next:Bool,muted:Bool){
        self.title.stringValue=title;self.artist.stringValue=artist
        controls["toggle"]?.image=sizedIcon(playing ? "pause":"play")
        controls["mute"]?.image=sizedIcon(muted ? "speaker-slash":"speaker-high")
        controls["previoustrack"]?.isEnabled=previous;controls["nexttrack"]?.isEnabled=next
        setAccessibilityLabel("Media: "+title+(playing ? ", playing":", paused"))
    }
    private func sizedIcon(_ name:String)->NSImage?{guard let image=VeilIcon.image(name)?.copy() as? NSImage else{return nil};image.size=NSSize(width:17,height:17);return image}
    override func layout(){
        super.layout();material.frame=bounds;title.frame=NSRect(x:14,y:11,width:bounds.width-50,height:19);artist.frame=NSRect(x:14,y:31,width:bounds.width-50,height:16)
        controls["dismiss"]?.frame=NSRect(x:bounds.width-31,y:9,width:23,height:23)
        for (index,id) in ["previoustrack","toggle","nexttrack","mute","source"].enumerated(){controls[id]?.frame=NSRect(x:13+CGFloat(index)*43,y:55,width:35,height:30)}
    }
}
