#!/usr/bin/env python3
"""Fetch a checksum-pinned official CEF build. No system packages or profiles."""
import hashlib,json,os,pathlib,shutil,subprocess,sys,tarfile,urllib.request,urllib.parse
project=pathlib.Path(__file__).resolve().parents[1]
work=pathlib.Path(os.environ.get('VEIL_WORK',str(project/'.work'))).resolve()
manifest=json.loads((project/'DEPENDENCIES.json').read_text())
deps=work/'dependencies';deps.mkdir(parents=True,exist_ok=True)
if sys.platform!='darwin' or subprocess.check_output(['uname','-m'],text=True).strip()!='arm64':
    raise SystemExit('This build targets Apple Silicon macOS.')
subprocess.run(['xcrun','--find','swiftc'],check=True,stdout=subprocess.DEVNULL)
toolchain=work/'toolchain'
if not (toolchain/'bin/cmake').exists():
    subprocess.run([sys.executable,'-m','venv',str(toolchain)],check=True)
    subprocess.run([str(toolchain/'bin/python'),'-m','pip','install','cmake==4.4.4','ninja==1.13.2','websocket-client==1.9.0'],check=True)
archive=deps/manifest['archive']
def checksum(path):
    digest=hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda:source.read(1024*1024),b''):digest.update(chunk)
    return digest.hexdigest()
if not archive.exists() or checksum(archive)!=manifest['sha256']:
    partial=archive.with_suffix(archive.suffix+'.partial')
    print('Downloading official CEF build…',flush=True)
    with urllib.request.urlopen(manifest['source']+urllib.parse.quote(manifest['archive'])) as source,partial.open('wb') as destination:shutil.copyfileobj(source,destination)
    if checksum(partial)!=manifest['sha256']:raise SystemExit('CEF checksum mismatch; archive not installed.')
    partial.replace(archive)
cef=deps/'cef'
if not (cef/'include/cef_version.h').exists():
    staging=deps/'cef-extract';staging.mkdir(exist_ok=True)
    with tarfile.open(archive,'r:bz2') as package:
        base=staging.resolve()
        for member in package.getmembers():
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):raise SystemExit('Unsupported archive entry')
            target=(base/member.name).resolve()
            if os.path.commonpath([str(base),str(target)])!=str(base):raise SystemExit('Unsafe archive path')
            if member.issym() or member.islnk():
                link=(target.parent/member.linkname).resolve() if member.issym() else (base/member.linkname).resolve()
                if os.path.commonpath([str(base),str(link)])!=str(base):raise SystemExit('Unsafe archive link')
        package.extractall(staging)
    candidates=list(staging.glob('cef_binary_*'))
    if len(candidates)!=1:raise SystemExit('Unexpected CEF archive layout')
    candidates[0].rename(cef);staging.rmdir()
print('Dependencies ready:',cef)
