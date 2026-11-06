#!/usr/bin/env python3
"""Idle-only sampling of the task's own QA app, without an in-app benchmark loop."""
import argparse,datetime,hashlib,json,pathlib,re,subprocess,time
from macos_usage import snapshot
p=argparse.ArgumentParser();p.add_argument('pid',type=int);p.add_argument('output',type=pathlib.Path);p.add_argument('--settle',type=int,default=60);p.add_argument('--samples',type=int,default=3);p.add_argument('--seconds',type=int,default=60);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
command=subprocess.check_output(['ps','-p',str(a.pid),'-o','args='],text=True).strip()
assert command.startswith('/private/tmp/VEIL-QA.app/Contents/MacOS/VEIL '),'Only the disposable VEIL QA app may be sampled.'
assert '--veil-benchmark' not in command,'Use the idle-only app launch.'
report={'started':datetime.datetime.now().astimezone().isoformat(),'pid':a.pid,'browser_age_at_sampler_start':subprocess.check_output(['ps','-p',str(a.pid),'-o','etime='],text=True).strip(),'settle_seconds':a.settle,'normalization':'100%=one logical core','cpu_method':'proc_pid_rusage V2: Mach ticks converted using mach_timebase_info; own + reaped-descendant nanoseconds over the live process family. Stable family required during each snapshot, not across the whole sample.','workload':'One about:blank page, no in-app benchmark controller, no input or accessibility inspection during samples.','executable_sha256':hashlib.sha256(pathlib.Path('/private/tmp/VEIL-QA.app/Contents/MacOS/VEIL').read_bytes()).hexdigest(),'os':subprocess.check_output(['sw_vers'],text=True),'hardware':subprocess.check_output(['sysctl','-n','hw.model','hw.memsize','hw.ncpu'],text=True),'power':subprocess.check_output(['pmset','-g','batt'],text=True),'samples':[]}
(a.output/'measurements.json').write_text(json.dumps(report,indent=2))
print('Settling',a.settle,'seconds.',flush=True);time.sleep(a.settle)
for i in range(a.samples):
    before=snapshot(a.pid);start=time.monotonic();time.sleep(a.seconds);after=snapshot(a.pid);elapsed=time.monotonic()-start
    delta_ns=after['cpu_ns']-before['cpu_ns']
    if delta_ns<0:raise RuntimeError('Process-family CPU counter decreased; sample is invalid.')
    current=after['processes']
    roles={}
    for line in subprocess.check_output(['ps','-p',','.join(map(str,current)),'-o','pid=,args='],text=True).splitlines():
        pid,args=line.strip().split(None,1);match=re.search(r'--type=(\S+)',args);roles[int(pid)]=match.group(1) if match else 'browser'
    sample={'duration_seconds':elapsed,'cpu_seconds':delta_ns/1e9,'percent_one_core':100*delta_ns/1e9/elapsed,'process_set_stable':set(before['processes'])==set(current),'before_counters':before,'after_counters':after,'current_process_roles':roles}
    raw=a.output/f'idle-{i+1}-footprint.json';cmd=['footprint','--noCategories','-j',str(raw)]
    for pid in current:cmd+=['-p',str(pid)]
    subprocess.run(cmd,check=True,stdout=subprocess.DEVNULL);memory=json.loads(raw.read_text())
    if memory.get('errors'):raise RuntimeError(memory['errors'])
    sample['footprint_mib']=memory['total footprint']/1048576
    report['samples'].append(sample);(a.output/'measurements.json').write_text(json.dumps(report,indent=2));print(json.dumps(sample),flush=True)
report['completed']=datetime.datetime.now().astimezone().isoformat();(a.output/'measurements.json').write_text(json.dumps(report,indent=2))
