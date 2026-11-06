#!/usr/bin/env python3
"""Collect native QA phase measurements. Launch VEIL --veil-qa --veil-benchmark first."""
import argparse,datetime,json,pathlib,statistics,subprocess,time
from macos_usage import snapshot
parser=argparse.ArgumentParser();parser.add_argument('profile_root',type=pathlib.Path);parser.add_argument('output',type=pathlib.Path);args=parser.parse_args()
args.output.mkdir(parents=True,exist_ok=True)
def process_times(root):
    rows=[]
    for line in subprocess.check_output(['ps','-axo','pid=,ppid=,time='],text=True).splitlines():
        parts=line.split()
        if len(parts)!=3:continue
        value=parts[2];days=0
        if '-' in value:day,value=value.split('-');days=int(day)
        seconds=0
        for component in value.split(':'):seconds=seconds*60+float(component)
        rows.append((int(parts[0]),int(parts[1]),seconds+days*86400))
    ids={root}
    while True:
        old=len(ids);ids.update(pid for pid,parent,_ in rows if parent in ids)
        if len(ids)==old:break
    return {pid:seconds for pid,_,seconds in rows if pid in ids}
def footprint(root,label):
    pids=process_times(root);path=args.output/(label+'-footprint.json')
    command=['footprint','--noCategories','-j',str(path)]
    for pid in pids:command+=['-p',str(pid)]
    result=subprocess.run(command,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
    if result.returncode:raise RuntimeError(result.stderr)
    data=json.loads(path.read_text())
    if data.get('errors'):raise RuntimeError(str(data['errors']))
    return {'bytes':data['total footprint'],'mib':data['total footprint']/1048576,'process_count':len(pids),'raw':path.name}
def idle_cpu(root,seconds=60):
    before=snapshot(root);start=time.monotonic();time.sleep(seconds);after=snapshot(root);elapsed=time.monotonic()-start
    used=(after['cpu_ns']-before['cpu_ns'])/1e9
    if used<0:raise RuntimeError('Process-family CPU counter decreased; sample is invalid.')
    return {'duration_seconds':elapsed,'cpu_seconds':used,'percent_one_core':100*used/elapsed,'before_counters':before,'after_counters':after,'method':'proc_pid_rusage with Mach timebase conversion and reaped-descendant CPU rollup'}
report={'started':datetime.datetime.now().astimezone().isoformat(),'os':subprocess.check_output(['sw_vers'],text=True),'hardware':subprocess.check_output(['sysctl','-n','hw.model','hw.memsize','hw.ncpu'],text=True),'power':subprocess.check_output(['pmset','-g','batt'],text=True),'empty':[],'trials':[],'normalization':'CPU 100%=one logical core. Footprint is Apple footprint process-tree total, not summed RSS.','fixture':'30 local pages; each has 8 MiB initialized Uint8Array, 100 static paragraphs, no animation or polling.'}
seen=set();deadline=time.monotonic()+1500
while time.monotonic()<deadline:
    paths=list(args.profile_root.glob('Build-*/qa-phase.json'))
    if not paths:time.sleep(.25);continue
    phase_path=max(paths,key=lambda p:p.stat().st_mtime)
    phase=json.loads(phase_path.read_text());name=phase['phase'];trial=phase['trial'];key=(trial,name)
    if key in seen:time.sleep(.25);continue
    seen.add(key);root=phase['pid'];report['build_fingerprint']=phase_path.parent.name.removeprefix('Build-');print('Measuring',trial,name,flush=True)
    if name=='error':raise RuntimeError(phase)
    if name=='empty':
        for index in range(3):
            sample=footprint(root,'empty-'+str(index+1));sample['cpu']=idle_cpu(root);report['empty'].append(sample)
    elif name in ('all-live','unloaded'):
        while len(report['trials'])<trial:report['trials'].append({})
        sample=footprint(root,f'trial-{trial}-{name}');sample['live']=phase.get('live');report['trials'][trial-1][name]=sample
        if name=='unloaded':
            previous=report['trials'][trial-1]['all-live']['bytes'];sample['reduction_percent']=100*(previous-sample['bytes'])/previous
    elif name=='complete':
        report['latency']=phase;break
    else:raise RuntimeError('Unexpected QA phase '+name)
    (args.output/'measurements.json').write_text(json.dumps(report,indent=2))
    (phase_path.parent/f'continue-{trial}-{name}').touch()
else:raise TimeoutError('Benchmark phase deadline exceeded')
for name,values in report['latency']['timings_ms'].items():
    ordered=sorted(values);report.setdefault('latency_summary',{})[name]={'count':len(values),'p50_ms':statistics.median(values),'p95_ms':ordered[int(.95*(len(ordered)-1))],'max_ms':max(values)}
report['completed']=datetime.datetime.now().astimezone().isoformat()
(args.output/'measurements.json').write_text(json.dumps(report,indent=2));print(json.dumps({'empty':report['empty'],'trials':report['trials'],'latency':report['latency_summary']},indent=2))
