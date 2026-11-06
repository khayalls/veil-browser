#include "Renderer.h"
#include "include/cef_v8.h"
#include "include/cef_frame.h"
#include "include/cef_process_message.h"
class VEReport:public CefV8Handler {
 CefRefPtr<CefFrame> frame;
public:
 explicit VEReport(CefRefPtr<CefFrame> f):frame(f){}
 bool Execute(const CefString&,CefRefPtr<CefV8Value>,const CefV8ValueList &args,CefRefPtr<CefV8Value>& result,CefString&) override {
  result=CefV8Value::CreateUndefined();
  if(args.size()!=1 || !args[0]->IsString())return true;
  auto text=args[0]->GetStringValue();if(text.length()>4096)return true;
  auto message=CefProcessMessage::Create("veil.telemetry");message->GetArgumentList()->SetString(0,text);frame->SendProcessMessage(PID_BROWSER,message);return true;
 }
private:IMPLEMENT_REFCOUNTING(VEReport);
};
class VERenderer : public CefApp, public CefRenderProcessHandler {
public:
 CefRefPtr<CefRenderProcessHandler> GetRenderProcessHandler() override {return this;}
 void OnContextCreated(CefRefPtr<CefBrowser>,CefRefPtr<CefFrame> frame,CefRefPtr<CefV8Context> context) override {
  context->GetGlobal()->SetValue("__veilReport",CefV8Value::CreateFunction("__veilReport",new VEReport(frame)),V8_PROPERTY_ATTRIBUTE_NONE);
  // This channel can report bounded UI/lifecycle hints only. It exposes no
  // native commands, filesystem, cookies, passwords, or shell capabilities.
  frame->ExecuteJavaScript(R"JS((function(report){
    'use strict';
    let dirty=false,queued=false,last='',capture=0,uploads=0,connections=0;
    const handlers=Object.create(null);
    const send=()=>{
      queued=false;
      const elements=Array.from(document.querySelectorAll('audio,video'));
      const active=elements.find(el=>!el.paused&&!el.ended);
      const metadata=navigator.mediaSession&&navigator.mediaSession.metadata;
      const state={dirty,playing:!!active,hasMedia:elements.length>0||!!metadata,capture:capture>0||connections>0,upload:uploads>0,
        mediaTitle:String(metadata&&metadata.title||document.title||'Media').slice(0,256),
        mediaArtist:String(metadata&&metadata.artist||'').slice(0,256),
        previous:!!handlers.previoustrack,next:!!handlers.nexttrack,
        horizontal:!!window.__veilHorizontalOwner};
      const encoded=JSON.stringify(state);if(encoded!==last){last=encoded;report(encoded)}
    };
    const schedule=()=>{if(!queued){queued=true;queueMicrotask(send)}};
    addEventListener('DOMContentLoaded',schedule,{once:true});
    for(const event of ['play','pause','ended','loadedmetadata','volumechange'])document.addEventListener(event,schedule,true);
    document.addEventListener('input',()=>{dirty=true;schedule()},true);
    document.addEventListener('change',()=>{dirty=true;schedule()},true);
    const originalFetch=window.fetch;
    if(originalFetch)window.fetch=function(...args){
      const request=args[0],options=args[1];const body=options&&options.body || (request instanceof Request && !['GET','HEAD'].includes(request.method));
      if(!body)return originalFetch.apply(this,args);
      uploads++;schedule();try{return originalFetch.apply(this,args).finally(()=>{uploads--;schedule()})}catch(error){uploads--;schedule();throw error}
    };
    const originalSend=XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send=function(body){
      if(body==null)return originalSend.call(this,body);
      uploads++;schedule();let pending=true;const done=()=>{if(pending){pending=false;uploads--;schedule()}};this.addEventListener('loadend',done,{once:true});
      try{return originalSend.call(this,body)}catch(error){done();throw error}
    };
    if(window.RTCPeerConnection){const Original=window.RTCPeerConnection;
      try{window.RTCPeerConnection=class extends Original{constructor(...args){super(...args);let protectedConnection=false;const changed=()=>{const active=!['closed','failed'].includes(this.connectionState);if(active!==protectedConnection){protectedConnection=active;connections+=active?1:-1;schedule()}};this.addEventListener('connectionstatechange',changed);changed()}}}catch(_){}
    }
    // Capture updates originate from standard media APIs; a failed request
    // grants nothing. Keep capture protected until all returned tracks end.
    if(navigator.mediaDevices){for(const method of ['getUserMedia','getDisplayMedia']){
      const original=navigator.mediaDevices[method];if(typeof original!=='function')continue;
      try{navigator.mediaDevices[method]=function(...args){return original.apply(this,args).then(stream=>{
        const tracks=stream.getTracks();capture+=tracks.length;schedule();
        for(const track of tracks)track.addEventListener('ended',()=>{capture=Math.max(0,capture-1);schedule()},{once:true});
        return stream;
      })}}catch(_){}
    }}
    if(navigator.mediaSession){const original=navigator.mediaSession.setActionHandler.bind(navigator.mediaSession);
      try{navigator.mediaSession.setActionHandler=function(action,handler){const result=original(action,handler);handlers[action]=handler;schedule();return result}}catch(_){}
    }
    Object.defineProperty(window,'__veilControl',{configurable:false,enumerable:false,value:function(action){
      const element=Array.from(document.querySelectorAll('audio,video')).find(el=>!el.paused)||document.querySelector('audio,video');
      if(action==='toggle')action=element&&!element.paused?'pause':'play';
      if(handlers[action]){try{handlers[action]({action})}catch(_){}}else if(element){if(action==='play')element.play().catch(()=>{});if(action==='pause')element.pause()}
      schedule();
    }});
    // Gesture arbitration follows the element under the pointer, including
    // horizontal scrollers, canvas-based editors and editable text.
    document.addEventListener('pointerover',event=>{
      let node=event.target,owns=false;
      while(node&&node.nodeType===1){
        if(node.tagName==='CANVAS'||node.isContentEditable||/^(INPUT|TEXTAREA)$/.test(node.tagName)){owns=true;break}
        const style=getComputedStyle(node);
        if(node.scrollWidth>node.clientWidth+2&&/(auto|scroll)/.test(style.overflowX)){owns=true;break}
        node=node.parentElement;
      }
      if(!!window.__veilHorizontalOwner!==owns){window.__veilHorizontalOwner=owns;schedule()}
    },true);
    document.addEventListener('pointerout',event=>{if(!event.relatedTarget&&window.__veilHorizontalOwner){window.__veilHorizontalOwner=false;schedule()}},true);
    schedule();
  })(window.__veilReport);delete window.__veilReport;)JS",frame->GetURL(),0);
 }
private: IMPLEMENT_REFCOUNTING(VERenderer);
};
CefRefPtr<CefApp> CreateVERenderer() {return new VERenderer();}
