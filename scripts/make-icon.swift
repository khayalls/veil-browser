import AppKit
let destination=CommandLine.arguments[1],size=NSSize(width:1024,height:1024)
let image=NSImage(size:size);image.lockFocus()
let outer=NSBezierPath(roundedRect:NSRect(x:58,y:58,width:908,height:908),xRadius:204,yRadius:204)
NSGradient(colors:[NSColor(srgbRed:0.35,green:0.34,blue:0.52,alpha:1),NSColor(srgbRed:0.13,green:0.13,blue:0.22,alpha:1)])!.draw(in:outer,angle:270)
NSColor(srgbRed:0.68,green:0.65,blue:0.91,alpha:0.15).setStroke();outer.lineWidth=6;outer.stroke()
// A small, original veil-shaped ghost: broad body and gently scalloped hem.
let ghost=NSBezierPath();ghost.move(to:NSPoint(x:277,y:306));ghost.line(to:NSPoint(x:277,y:529));ghost.curve(to:NSPoint(x:747,y:529),controlPoint1:NSPoint(x:277,y:843),controlPoint2:NSPoint(x:747,y:843));ghost.line(to:NSPoint(x:747,y:306))
ghost.curve(to:NSPoint(x:630,y:306),controlPoint1:NSPoint(x:711,y:266),controlPoint2:NSPoint(x:668,y:266));ghost.curve(to:NSPoint(x:512,y:306),controlPoint1:NSPoint(x:591,y:353),controlPoint2:NSPoint(x:551,y:353));ghost.curve(to:NSPoint(x:394,y:306),controlPoint1:NSPoint(x:473,y:266),controlPoint2:NSPoint(x:433,y:266));ghost.curve(to:NSPoint(x:277,y:306),controlPoint1:NSPoint(x:355,y:353),controlPoint2:NSPoint(x:316,y:353));ghost.close()
let shadow=NSShadow();shadow.shadowColor=NSColor.black.withAlphaComponent(0.24);shadow.shadowBlurRadius=34;shadow.shadowOffset=NSSize(width:0,height:-20);NSGraphicsContext.saveGraphicsState();shadow.set()
NSGradient(colors:[NSColor(srgbRed:0.94,green:0.91,blue:1,alpha:1),NSColor(srgbRed:0.68,green:0.65,blue:0.88,alpha:1)])!.draw(in:ghost,angle:270);NSGraphicsContext.restoreGraphicsState()
NSColor(srgbRed:0.23,green:0.22,blue:0.36,alpha:1).setFill()
for x:CGFloat in [420,575]{NSBezierPath(roundedRect:NSRect(x:x,y:511,width:29,height:57),xRadius:14,yRadius:14).fill()}
let smile=NSBezierPath();smile.move(to:NSPoint(x:479,y:473));smile.curve(to:NSPoint(x:545,y:473),controlPoint1:NSPoint(x:493,y:451),controlPoint2:NSPoint(x:531,y:451));smile.lineWidth=12;smile.lineCapStyle = .round;smile.stroke()
image.unlockFocus()
let rep=NSBitmapImageRep(data:image.tiffRepresentation!)!;try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:destination))
