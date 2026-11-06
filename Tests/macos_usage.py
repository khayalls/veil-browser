"""macOS process-family CPU counters, including reaped child processes.

XNU rolls each reaped process's own and descendant CPU into its parent's
ri_child_* counters. Summing own + reaped-descendant counters over the live
family therefore preserves CPU across helper exits. Re-enumerate around the
read to reject a snapshot taken during a process transition.

Primary definitions: Apple SDK sys/resource.h; apple-oss-distributions/xnu
bsd/kern/kern_resource.c (update_rusage_info_child) and kern_exit.c (reap).
"""
import ctypes
import os
import resource
import subprocess
import time

_names = ('user system pkg_wakeups interrupt_wakeups pageins wired resident '
          'footprint started exited child_user child_system child_pkg_wakeups '
          'child_interrupt_wakeups child_pageins child_elapsed disk_read disk_write').split()

class _RUsageV2(ctypes.Structure):
    _fields_ = [('uuid', ctypes.c_ubyte * 16)] + [(name, ctypes.c_uint64) for name in _names]

_lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
_lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
_lib.proc_pid_rusage.restype = ctypes.c_int

class _Timebase(ctypes.Structure):
    _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]

_system = ctypes.CDLL('/usr/lib/libSystem.B.dylib')
_system.mach_timebase_info.argtypes = [ctypes.POINTER(_Timebase)]
_system.mach_timebase_info.restype = ctypes.c_int
_timebase = _Timebase()
if _system.mach_timebase_info(ctypes.byref(_timebase)) or not _timebase.denom:
    raise RuntimeError('Unable to read the Mach timebase.')

def _nanoseconds(ticks):
    return ticks * _timebase.numer // _timebase.denom

def usage(pid):
    value = _RUsageV2()
    if _lib.proc_pid_rusage(pid, 2, ctypes.byref(value)):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code), pid)
    return {'own_ns': _nanoseconds(value.user + value.system),
            'reaped_descendants_ns': _nanoseconds(value.child_user + value.child_system),
            'started_abstime': value.started}

def family(root):
    rows = [tuple(map(int, line.split())) for line in
            subprocess.check_output(['ps', '-axo', 'pid=,ppid='], text=True).splitlines()]
    ids = {root}
    if not any(pid == root for pid, _ in rows):
        raise ProcessLookupError('QA browser exited.')
    while True:
        previous = len(ids)
        ids.update(pid for pid, parent in rows if parent in ids)
        if len(ids) == previous:
            return ids

def snapshot(root):
    for _ in range(5):
        before = family(root)
        try:
            counters = {pid: usage(pid) for pid in sorted(before)}
        except ProcessLookupError:
            continue
        if before == family(root):
            return {'processes': counters,
                    'cpu_ns': sum(v['own_ns'] + v['reaped_descendants_ns'] for v in counters.values())}
    raise RuntimeError('Process family kept changing during counter reads; sample is invalid.')

def self_test():
    """Calibrate nanoseconds and verify live child CPU rolls into its parent."""
    before = usage(os.getpid())
    old = resource.getrusage(resource.RUSAGE_CHILDREN)
    child = os.fork()
    if child == 0:
        start = time.process_time()
        while time.process_time() - start < 0.30:
            pass
        os._exit(0)
    try:
        time.sleep(0.12)
        parent_live, child_live = usage(os.getpid()), usage(child)
        live_total = sum(v['own_ns'] + v['reaped_descendants_ns'] for v in [parent_live, child_live])
        os.waitpid(child, 0)
        after = usage(os.getpid())
        new = resource.getrusage(resource.RUSAGE_CHILDREN)
        rolled_seconds = (after['reaped_descendants_ns'] - before['reaped_descendants_ns']) / 1e9
        reference_seconds = new.ru_utime + new.ru_stime - old.ru_utime - old.ru_stime
        assert 0.28 <= rolled_seconds <= 0.65, (rolled_seconds, reference_seconds)
        assert abs(rolled_seconds - reference_seconds) < 0.02, (rolled_seconds, reference_seconds)
        assert after['own_ns'] + after['reaped_descendants_ns'] >= live_total
        return {'passed': True, 'kernel_child_cpu_seconds': rolled_seconds,
                'getrusage_child_cpu_seconds': reference_seconds,
                'mach_timebase_numer': _timebase.numer, 'mach_timebase_denom': _timebase.denom,
                'live_to_reaped_counter_monotonic': True}
    finally:
        try:
            os.kill(child, 9)
            os.waitpid(child, 0)
        except ProcessLookupError:
            pass
        except ChildProcessError:
            pass

if __name__ == '__main__':
    import json
    print(json.dumps(self_test(), indent=2))
