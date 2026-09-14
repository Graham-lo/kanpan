"""Bounded anonymous-client budgets. No user/account secrets are collected."""
import os
from pathlib import Path
import threading
import time


class Bucket:
    def __init__(self, rate, burst, now=None):
        self.rate, self.burst = rate, burst
        self.tokens = burst
        self.at = time.monotonic() if now is None else now

    def take(self, amount=1, now=None):
        now = time.monotonic() if now is None else now
        self.tokens = min(self.burst, self.tokens + max(0, now - self.at) * self.rate)
        self.at = now
        if amount > self.tokens:
            return False
        self.tokens -= amount
        return True


class Capacity:
    """Sampled host headroom; quick bounded reductions, slow recovery avoid flapping."""
    def __init__(self, clients=128, bytes_per_second=1_500_000):
        self.maximum_clients = clients
        self.maximum_bytes = bytes_per_second
        self.scale = 1.0

    def update(self, cpu=0, memory_available=1, process_memory=0, network_ratio=0):
        pressure = max(cpu, max(0, 1 - memory_available / 0.25), process_memory, network_ratio)
        target = max(0.2, min(1.0, (1 - pressure) / 0.3))
        step = -0.2 if target < self.scale else 0.05
        self.scale = max(target, self.scale + step) if step < 0 else min(target, self.scale + step)

    @property
    def clients(self):
        return max(8, int(self.maximum_clients * self.scale))

    @property
    def bytes_per_second(self):
        return max(32_000, int(self.maximum_bytes * self.scale))


class HostSampler:
    def __init__(self, memory_limit=256 * 1024 * 1024, network_limit=5_000_000):
        self.memory_limit, self.network_limit = memory_limit, network_limit
        self.previous_cpu = self.previous_net = None
        self.previous_time = time.monotonic()

    def sample(self):
        try:
            cpu = [int(v) for v in Path('/proc/stat').read_text().splitlines()[0].split()[1:9]]
            total, idle = sum(cpu), cpu[3] + cpu[4]
            busy = 0 if self.previous_cpu is None else 1 - (idle - self.previous_cpu[1]) / max(1, total - self.previous_cpu[0])
            self.previous_cpu = total, idle
            mem = dict((k, int(v.split()[0])) for k, v in (line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines()))
            rss = int(Path('/proc/self/statm').read_text().split()[1]) * os.sysconf('SC_PAGE_SIZE')
            interface = next((line.split()[0] for line in Path('/proc/net/route').read_text().splitlines()[1:] if line.split()[1] == '00000000'), None)
            network = sum(int(line.split(':')[1].split()[8]) for line in Path('/proc/net/dev').read_text().splitlines()[2:] if line.split(':')[0].strip() == interface)
            now = time.monotonic()
            output = 0 if self.previous_net is None else max(0, network - self.previous_net) / max(.1, now - self.previous_time)
            self.previous_net, self.previous_time = network, now
            return dict(cpu=max(0, min(1, busy)), memory_available=mem['MemAvailable'] / mem['MemTotal'],
                        process_memory=rss / self.memory_limit, network_ratio=output / self.network_limit)
        except (OSError, ValueError, KeyError, IndexError, ZeroDivisionError):
            return {}  # Non-Linux offline tests keep conservative configured limits.


class HTTPGuard:
    """Per-source rate/concurrency plus bounded bookkeeping, safe from key flooding."""
    def __init__(self, limit=2048):
        self.limit = limit
        self.peers = {}
        self.lock = threading.Lock()

    def enter(self, key, now=None):
        now = time.monotonic() if now is None else now
        with self.lock:
            if key not in self.peers:
                self.peers = {k: v for k, v in self.peers.items() if v[1] or now - v[2] < 120}
                if len(self.peers) >= self.limit:
                    return False
                self.peers[key] = [Bucket(2, 8, now), 0, now]
            peer = self.peers[key]
            peer[2] = now
            if peer[1] >= 2 or not peer[0].take(now=now):
                return False
            peer[1] += 1
            return True

    def leave(self, key):
        with self.lock:
            if key in self.peers:
                self.peers[key][1] = max(0, self.peers[key][1] - 1)
