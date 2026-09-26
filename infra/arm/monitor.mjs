import { spawnSync } from 'node:child_process';
import { appendFile, mkdir, readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { parseArgs } from 'node:util';
import { assertLocalDockerEndpoint } from './docker-endpoint.mjs';

function docker(args) {
  const result = spawnSync('docker', args, { encoding: 'utf8', timeout: 10000 });
  if (result.error || result.status !== 0) throw new Error('Docker monitoring failed; confirm local Docker permission');
  return result.stdout;
}

try {
  if (process.platform !== 'linux' || process.arch !== 'arm64') throw new Error('Monitor requires the native Linux ARM64 Docker host');
  const context = JSON.parse(docker(['context', 'inspect']))[0];
  assertLocalDockerEndpoint(context);
  const { values } = parseArgs({ options: { seconds: { type: 'string', default: '60' }, out: { type: 'string' } } });
  const seconds = Number(values.seconds);
  if (!Number.isInteger(seconds) || seconds < 1 || seconds > 3600) throw new Error('Use 1..3600 seconds');
  const ids = docker(['ps', '--filter', 'label=com.docker.compose.project=gnom-arm-stand', '--format', '{{.ID}}']).trim().split('\n').filter(Boolean);
  if (ids.length !== 3) throw new Error('Expected three running stand containers');
  const output = resolve(values.out ?? `infra/arm/results/resources-${Date.now()}.ndjson`);
  await mkdir(dirname(output), { recursive: true });
  const until = Date.now() + seconds * 1000;
  while (Date.now() < until) {
    const inspected = JSON.parse(docker(['inspect', ...ids]));
    const samples = docker(['stats', '--no-stream', '--format', '{{json .}}', ...ids]).trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
    for (const sample of samples) {
      const container = inspected.find(item => item.Id.startsWith(sample.ID));
      let mainProcessRssKiB = null;
      try {
        const status = await readFile(`/proc/${container.State.Pid}/status`, 'utf8');
        const match = status.match(/^VmRSS:\s+(\d+)\s+kB$/m);
        if (match) mainProcessRssKiB = Number(match[1]);
      } catch { /* Restricted procfs remains an explicit unavailable metric. */ }
      await appendFile(output, JSON.stringify({ at: new Date().toISOString(), name: sample.Name, cpuPercent: Number.parseFloat(sample.CPUPerc), containerMemory: sample.MemUsage, memoryPercent: Number.parseFloat(sample.MemPerc), mainProcessRssKiB, pids: sample.PIDs, networkIO: sample.NetIO, blockIO: sample.BlockIO, oomKilled: container?.State.OOMKilled, health: container?.State.Health?.Status ?? null }) + '\n');
    }
    await delay(1000);
  }
  console.log(`Resource samples saved: ${output}`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
