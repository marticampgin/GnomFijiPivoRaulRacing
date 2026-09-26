type Close = () => Promise<unknown>;
interface Signals {
  on(event: 'SIGINT' | 'SIGTERM', listener: () => void): unknown;
  off(event: 'SIGINT' | 'SIGTERM', listener: () => void): unknown;
}

export class LocalLifecycle {
  private readonly controller = new AbortController();
  private readonly resources: Array<() => void> = [];
  private readonly closing: Promise<unknown>[] = [];
  private resolveStopped!: () => void;
  readonly stopped = new Promise<void>((resolve) => { this.resolveStopped = resolve; });
  readonly signal = this.controller.signal;

  own(close: Close): void {
    let scheduled = false;
    const dispose = () => {
      if (scheduled) return;
      scheduled = true;
      const pending = Promise.resolve().then(close);
      this.closing.push(pending);
      void pending.catch(() => {});
    };
    this.resources.push(dispose);
    if (this.signal.aborted) dispose();
  }

  checkpoint(): void { this.signal.throwIfAborted(); }

  stop(): void {
    if (this.signal.aborted) return;
    this.controller.abort();
    this.resolveStopped();
    // Drain independently: a pool waiting on a query must not delay stopping PostgreSQL.
    for (const dispose of [...this.resources].reverse()) dispose();
  }

  async settled(): Promise<void> {
    const results = await Promise.allSettled(this.closing);
    const failures = results.filter((result) => result.status === 'rejected').map((result) => result.reason);
    if (failures.length) throw new AggregateError(failures, 'Local resource cleanup failed');
  }
}

export async function withLocalShutdown(start: (lifecycle: LocalLifecycle) => Promise<void>, signals: Signals = process): Promise<void> {
  const lifecycle = new LocalLifecycle();
  const stop = () => lifecycle.stop();
  signals.on('SIGINT', stop);
  signals.on('SIGTERM', stop);
  let failure: unknown;
  try {
    await start(lifecycle);
    await lifecycle.stopped;
  } catch (error) {
    if (!lifecycle.signal.aborted) failure = error;
  } finally {
    lifecycle.stop();
    try { await lifecycle.settled(); }
    catch (error) { failure = failure ? new AggregateError([failure, error], 'Local startup and cleanup failed') : error; }
    signals.off('SIGINT', stop);
    signals.off('SIGTERM', stop);
  }
  if (failure) throw failure;
}
