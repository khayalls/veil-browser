import AppKit

enum VeilIcon {
    static func image(_ name:String)->NSImage? {NSImage(named:NSImage.Name(name))}
}
enum VeilPalette {
    static let accents:[NSColor] = [
        NSColor(srgbRed:0.64,green:0.60,blue:0.83,alpha:1),
        NSColor(srgbRed:0.47,green:0.68,blue:0.64,alpha:1),
        NSColor(srgbRed:0.86,green:0.62,blue:0.52,alpha:1),
        NSColor(srgbRed:0.52,green:0.68,blue:0.86,alpha:1),
        NSColor(srgbRed:0.80,green:0.56,blue:0.68,alpha:1),
        NSColor(srgbRed:0.81,green:0.74,blue:0.47,alpha:1)
    ]
    static func accent(_ i:Int)->NSColor {accents[((i % accents.count)+accents.count)%accents.count]}
    static func accent(_ space:VeilSpace)->NSColor{space.appearance?.accentHex.flatMap(color) ?? accent(space.color)}
    static func color(_ hex:String)->NSColor?{guard hex.count==7,hex.hasPrefix("#"),let value=UInt32(hex.dropFirst(),radix:16) else{return nil};return NSColor(srgbRed:CGFloat((value>>16)&255)/255,green:CGFloat((value>>8)&255)/255,blue:CGFloat(value&255)/255,alpha:1)}
    static func hex(_ color:NSColor)->String{let rgb=color.usingColorSpace(.sRGB) ?? .black;func byte(_ value:CGFloat)->Int{Int(min(255,max(0,(value*255).rounded())))};return String(format:"#%02X%02X%02X",byte(rgb.redComponent),byte(rgb.greenComponent),byte(rgb.blueComponent))}
}
func veilLabel(_ text:String,size:CGFloat=13,weight:NSFont.Weight = .regular,color:NSColor = .labelColor)->NSTextField {
    let field=NSTextField(labelWithString:text)
    field.font = .systemFont(ofSize:size,weight:weight);field.textColor=color
    field.lineBreakMode = .byTruncatingTail;field.maximumNumberOfLines=1
    return field
}
class FlippedView:NSView {
    var onLayout:(()->Void)?
    override var isFlipped:Bool {true}
    override func layout(){super.layout();onLayout?()}
}
final class WorkspaceRootView:FlippedView {
    var tint:NSColor = VeilPalette.accent(0) {didSet{needsDisplay=true}}
    var background:NSColor = .windowBackgroundColor{didSet{needsDisplay=true}}
    var gradient=true{didSet{needsDisplay=true}}
    var chromeOpacity:CGFloat=0.92{didSet{needsDisplay=true}}
    var onPointer:((NSEvent)->Void)?
    private var tracking:NSTrackingArea?
    override func draw(_ dirtyRect:NSRect) {
        NSColor.clear.setFill();bounds.fill(using:.copy)
        let opacity=NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1:chromeOpacity
        let top=background.blended(withFraction:0.16,of:tint) ?? background
        if gradient{NSGradient(starting:top.withAlphaComponent(opacity),ending:background.withAlphaComponent(opacity))?.draw(in:bounds,angle:-45)}else{background.withAlphaComponent(opacity).setFill();bounds.fill()}
    }
    override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking{removeTrackingArea(tracking)};let t=NSTrackingArea(rect:bounds,options:[.mouseMoved,.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self);addTrackingArea(t);tracking=t}
    override func mouseMoved(with event:NSEvent){onPointer?(event)}
    override func mouseExited(with event:NSEvent){onPointer?(event)}
}
class ActionButton:NSButton {
    var onPress:(()->Void)?
    var onDrop:((NSPasteboard)->Bool)?{didSet{if onDrop != nil{registerForDraggedTypes([.veilTab,.veilFolder,.URL,.string])}else{unregisterDraggedTypes()}}}
    var onDragHover:(()->Void)?
    private var dragHoverWork:DispatchWorkItem?
    var selectedState=false {didSet{updateBackground()}}
    var accent:NSColor = .controlAccentColor
    var hovered=false
    var restingBackgroundAlpha:CGFloat=0{didSet{updateBackground()}}
    private var tracking:NSTrackingArea?
    init(icon:String,title:String="",help:String,action:@escaping()->Void) {
        super.init(frame:.zero)
        self.title=title
        if let original=VeilIcon.image(icon),let sized=original.copy() as? NSImage{sized.size=NSSize(width:17,height:17);image=sized}
        imagePosition=title.isEmpty ? .imageOnly:.imageLeading
        imageScaling = .scaleNone
        isBordered=false;bezelStyle = .regularSquare;setButtonType(.momentaryChange)
        font = .systemFont(ofSize:12,weight:.medium);contentTintColor = .secondaryLabelColor
        toolTip=help;setAccessibilityLabel(help)
        onPress=action;target=self;self.action=#selector(pressed)
        wantsLayer=true;layer?.cornerRadius=8
    }
    required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
    @objc private func pressed(){onPress?()}
    override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking{removeTrackingArea(tracking)};let t=NSTrackingArea(rect:bounds,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect],owner:self);addTrackingArea(t);tracking=t}
    override func mouseEntered(with event:NSEvent){hovered=true;updateBackground()}
    override func mouseExited(with event:NSEvent){hovered=false;updateBackground()}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation{guard onDrop != nil else{return []};hovered=true;updateBackground();let item=DispatchWorkItem{ [weak self] in self?.onDragHover?() };dragHoverWork=item;DispatchQueue.main.asyncAfter(deadline:.now()+0.45,execute:item);return .move}
    override func draggingExited(_ sender:NSDraggingInfo?){dragHoverWork?.cancel();hovered=false;updateBackground()}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool{dragHoverWork?.cancel();hovered=false;updateBackground();return onDrop?(sender.draggingPasteboard) ?? false}
    private func updateBackground(){layer?.backgroundColor=(selectedState ? accent.withAlphaComponent(0.18):NSColor.labelColor.withAlphaComponent(hovered ? max(0.09,restingBackgroundAlpha):restingBackgroundAlpha)).cgColor}
}
final class AddressButton:ActionButton{
    private let glyph=NSImageView(),label=veilLabel("VEIL",size:12,weight:.medium,color:.secondaryLabelColor)
    init(action:@escaping()->Void){
        super.init(icon:"",help:"Change address",action:action);image=nil
        glyph.image=VeilIcon.image("link");glyph.contentTintColor = .secondaryLabelColor
        addSubview(glyph);addSubview(label);restingBackgroundAlpha=0.055;layer?.cornerRadius=14;layer?.borderWidth=0.5;layer?.borderColor=NSColor.labelColor.withAlphaComponent(0.10).cgColor
    }
    required init?(coder:NSCoder){fatalError()}
    func setAddress(_ value:String){label.stringValue=value;setAccessibilityValue(value);needsLayout=true}
    override func hitTest(_ point:NSPoint)->NSView?{super.hitTest(point)==nil ? nil:self}
    override func layout(){super.layout();let measured=(label.stringValue as NSString).size(withAttributes:[.font:label.font ?? NSFont.systemFont(ofSize:12)]).width+12,textWidth=min(max(0,bounds.width-58),measured),start=max(14,(bounds.width-textWidth-22)/2);glyph.frame=NSRect(x:start,y:bounds.midY-7,width:14,height:14);label.frame=NSRect(x:start+22,y:bounds.midY-9.5,width:textWidth,height:19)}
}
final class ContentCornerMask:NSView {
    var color:NSColor = .windowBackgroundColor {didSet{needsDisplay=true}}
    var radius:CGFloat=14
    override var isOpaque:Bool{false}
    override func hitTest(_ point:NSPoint)->NSView?{nil}
    override func draw(_ dirtyRect:NSRect) {
        let path=NSBezierPath(rect:bounds);path.append(NSBezierPath(roundedRect:bounds,xRadius:radius,yRadius:radius));path.windingRule = .evenOdd
        color.setFill();path.fill()
    }
}
final class SwipeFeedback:NSView{
    private var amount:CGFloat=0
    private var animationID=0
    func update(amount value:CGFloat,complete:Bool,reduceMotion:Bool){
        animationID+=1;let generation=animationID
        if complete || abs(value)<0.005{
            guard !isHidden else{return}
            if reduceMotion{isHidden=true;amount=0;return}
            NSAnimationContext.runAnimationGroup({context in context.duration=0.16;self.animator().alphaValue=0},completionHandler:{[weak self] in guard let self,self.animationID==generation else{return};self.isHidden=true;self.amount=0;self.alphaValue=1})
        }else{amount=value;isHidden=false;alphaValue=1;needsDisplay=true}
    }
    override var isOpaque:Bool{false}
    override func hitTest(_ point:NSPoint)->NSView?{nil}
    override func draw(_ rect:NSRect){
        let p=min(1,abs(amount)/0.30),eased=1-pow(1-p,3),fade=min(1,abs(amount)/0.12),size:CGFloat=48*(0.70+0.30*eased)
        let x=amount>0 ? 12+10*eased:bounds.width-size-12-10*eased,y=bounds.midY-size/2
        NSColor.windowBackgroundColor.withAlphaComponent(0.92*fade).setFill();NSBezierPath(ovalIn:NSRect(x:x,y:y,width:size,height:size)).fill()
        let iconSize=size*0.48;VeilIcon.image(amount>0 ? "arrow-left":"arrow-right")?.draw(in:NSRect(x:x+(size-iconSize)/2,y:y+(size-iconSize)/2,width:iconSize,height:iconSize),from:.zero,operation:.sourceOver,fraction:fade)
    }
}
final class ErrorPageView:FlippedView{
    let title=veilLabel("Couldn't load this page.",size:26,weight:.semibold),detail=veilLabel("Check your connection, then try again.",size:13,color:.secondaryLabelColor)
    private let retry:ActionButton
    init(retry:@escaping()->Void){self.retry=ActionButton(icon:"arrow-clockwise",title:" Try again",help:"Retry this page",action:retry);super.init(frame:.zero);[title,detail,self.retry].forEach{addSubview($0)};title.alignment = .center;detail.alignment = .center;detail.maximumNumberOfLines=3;detail.lineBreakMode = .byWordWrapping}
    required init?(coder:NSCoder){fatalError()}
    func focusRetry(){window?.makeFirstResponder(retry)}
    override func draw(_ rect:NSRect){NSColor.windowBackgroundColor.setFill();bounds.fill()}
    override func layout(){super.layout();title.frame=NSRect(x:30,y:bounds.midY-65,width:bounds.width-60,height:44);detail.frame=NSRect(x:45,y:bounds.midY-8,width:bounds.width-90,height:60);retry.frame=NSRect(x:bounds.midX-70,y:bounds.midY+72,width:140,height:34)}
}
final class SidebarResizeHandle:NSView {
    var onResize:((CGFloat)->Void)?
    override func resetCursorRects(){addCursorRect(bounds,cursor:.resizeLeftRight)}
    override func mouseDown(with event:NSEvent) {
        guard let window else{return}
        while let next=window.nextEvent(matching:[.leftMouseDragged,.leftMouseUp]) {
            if next.type == .leftMouseUp {break}
            onResize?(next.locationInWindow.x)
        }
    }
}
final class EmptyPageView:FlippedView {
    private let ghost=NSImageView()
    private let title=veilLabel("A little more room.",size:30,weight:.semibold)
    private let subtitle=veilLabel("Press ⌘T. Your next stop is one thought away.",size:14,color:.secondaryLabelColor)
    private let newTab:ActionButton
    init(open:@escaping()->Void){
        newTab=ActionButton(icon:"plus",title:"  Go somewhere",help:"Open command bar",action:open)
        super.init(frame:.zero)
        ghost.image=VeilIcon.image("ghost-duotone");ghost.contentTintColor=VeilPalette.accent(0)
        [ghost,title,subtitle,newTab].forEach{addSubview($0)}
        setAccessibilityLabel("VEIL home")
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){
        super.layout();let center=bounds.midY-35
        ghost.frame=NSRect(x:bounds.midX-36,y:center-110,width:72,height:72)
        title.frame=NSRect(x:20,y:center-12,width:bounds.width-40,height:40);title.alignment = .center
        subtitle.frame=NSRect(x:20,y:center+38,width:bounds.width-40,height:24);subtitle.alignment = .center
        newTab.frame=NSRect(x:bounds.midX-86,y:center+88,width:172,height:36)
    }
}
