import AppKit

/// Native navigation/control chrome only. Chromium stays in a separate,
/// non-layer-backed sibling so its accelerated surface keeps rendering.
final class GlassSurface:FlippedView{
    let content=FlippedView()
    private var effect:NSView?
    private let radius:CGFloat
    private let interactive:Bool
    private let fallbackMaterial:NSVisualEffectView.Material
    var enabled=true{didSet{if enabled != oldValue{rebuild()}}}
    var tint:NSColor?{didSet{if #available(macOS 26.0,*),let glass=effect as? NSGlassEffectView{glass.tintColor=tint}}}
    init(radius:CGFloat=20,interactive:Bool=true,fallback:NSVisualEffectView.Material = .popover){
        self.radius=radius;self.interactive=interactive;fallbackMaterial=fallback
        super.init(frame:.zero)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(displayOptionsChanged),name:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil)
        rebuild()
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{NSWorkspace.shared.notificationCenter.removeObserver(self)}
    @objc private func displayOptionsChanged(){rebuild()}
    private func rebuild(){
        content.removeFromSuperview();effect?.removeFromSuperview();effect=nil
        if enabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency{
            if #available(macOS 26.0,*){
                let glass=NSGlassEffectView();glass.style = .regular;glass.cornerRadius=radius;glass.tintColor=tint
                if #available(macOS 27.0,*){glass.effectIsInteractive=interactive}
                glass.contentView=content;addSubview(glass);effect=glass
                setAccessibilityIdentifier("veil.material.liquid-glass")
            }else{
                let material=NSVisualEffectView();material.material=fallbackMaterial;material.blendingMode = .behindWindow;material.state = .active
                material.wantsLayer=true;material.layer?.cornerRadius=radius;material.layer?.masksToBounds=true
                material.addSubview(content);addSubview(material);effect=material
            }
        }else{
            let solid=NSView();solid.wantsLayer=true;solid.layer?.cornerRadius=radius;solid.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
            solid.addSubview(content);addSubview(solid);effect=solid
        }
        needsLayout=true
    }
    override func layout(){super.layout();effect?.frame=bounds;content.frame=bounds}
}
