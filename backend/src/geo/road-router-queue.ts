/** One private routing worker, with bounded waiting instead of interrupting it. */
export class RoadRouterQueue {
  private active = false;
  private waiting: Array<{start: () => void; reject: (error: Error) => void; timer: ReturnType<typeof setTimeout>}> = [];
  constructor(private readonly limit = 8, private readonly waitMs = 5000) {}
  run<T>(work: () => Promise<T>): Promise<T> {
    if (this.active && this.waiting.length >= this.limit) return Promise.reject(new Error('Road router queue full'));
    return new Promise<T>((resolve, reject) => {
      const start = () => {
        this.active = true;
        Promise.resolve().then(work).then(resolve, reject).finally(() => {
          this.active = false;
          const next = this.waiting.shift();
          if (next) { clearTimeout(next.timer); next.start(); }
        });
      };
      if (!this.active) { start(); return; }
      const entry = {start, reject, timer: undefined as ReturnType<typeof setTimeout>};
      entry.timer = setTimeout(() => {
        const index = this.waiting.indexOf(entry);
        if (index >= 0) this.waiting.splice(index, 1);
        reject(new Error('Road router queue wait exceeded'));
      }, this.waitMs);
      this.waiting.push(entry);
    });
  }
}
