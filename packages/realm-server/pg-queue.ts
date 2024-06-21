import isEqual from 'lodash/isEqual';
import {
  type Queue,
  type PgPrimitive,
  type Expression,
  param,
  separatedByCommas,
  addExplicitParens,
  any,
  every,
  query,
  logger,
  asExpressions,
  Deferred,
  Job,
  setErrorReporter,
} from '@cardstack/runtime-common';
import PgAdapter from './pg-adapter';
import * as Sentry from '@sentry/node';

const log = logger('queue');

interface JobsTable {
  id: number;
  category: string;
  args: Record<string, any>;
  status: 'unfulfilled' | 'resolved' | 'rejected';
  created_at: Date;
  finished_at: Date;
  queue: string;
  result: Record<string, any>;
}

interface QueueTable {
  queue_name: string;
  category: string;
  status: 'idle' | 'working';
}

export interface QueueOpts {
  queueName?: string;
}

const defaultQueueOpts: Required<QueueOpts> = Object.freeze({
  queueName: 'default',
});

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.SENTRY_ENVIRONMENT || 'development',
  });
  setErrorReporter(Sentry.captureException);
}

// Tracks a job that should loop with a timeout and an interruptible sleep.
class WorkLoop {
  private internalWaker: Deferred<void> | undefined;
  private timeout: NodeJS.Timeout | undefined;
  private _shuttingDown = false;
  private runnerPromise: Promise<void> | undefined;

  constructor(
    private label: string,
    private pollInterval: number,
  ) {}

  // 1. Your fn should loop until workLoop.shuttingDown is true.
  // 2. When it has no work to do, it should await workLoop.sleep().
  // 3. It can be awoke with workLoop.wake().
  // 4. Remember to await workLoop.shutdown() when you're done.
  //
  // This is separate from the constructor so you can store your WorkLoop first,
  // *before* the runner starts doing things.
  run(fn: (loop: WorkLoop) => Promise<void>) {
    this.runnerPromise = fn(this);
  }

  async shutDown(): Promise<void> {
    log.debug(`[workloop %s] shutting down`, this.label);
    this._shuttingDown = true;
    this.wake();
    await this.runnerPromise;
    log.debug(`[workloop %s] completed shutdown`, this.label);
  }

  get shuttingDown(): boolean {
    return this._shuttingDown;
  }

  private get waker() {
    if (!this.internalWaker) {
      this.internalWaker = new Deferred();
    }
    return this.internalWaker;
  }

  wake() {
    log.debug(`[workloop %s] waking up`, this.label);
    this.waker.fulfill();
  }

  async sleep() {
    if (this.shuttingDown) {
      return;
    }
    let timerPromise = new Promise((resolve) => {
      this.timeout = setTimeout(resolve, this.pollInterval);
    });
    log.debug(`[workloop %s] entering promise race`, this.label);
    await Promise.race([this.waker.promise, timerPromise]);
    log.debug(`[workloop] leaving promise race`, this.label);
    if (this.timeout != null) {
      clearTimeout(this.timeout);
    }
    this.internalWaker = undefined;
  }
}

export default class PgQueue implements Queue {
  #hasStarted = false;
  #isDestroyed = false;

  private pollInterval = 10000;
  private handlers: Map<string, Function> = new Map();
  private notifiers: Map<number, Deferred<any>> = new Map();

  private jobRunner: WorkLoop | undefined;
  private notificationRunner: WorkLoop | undefined;

  constructor(private pgClient: PgAdapter) {}

  private async query(expression: Expression) {
    return await query(this.pgClient, expression);
  }

  private addNotifier(id: number, n: Deferred<any>) {
    if (!this.notificationRunner && !this.#isDestroyed) {
      this.notificationRunner = new WorkLoop(
        'notificationRunner',
        this.pollInterval,
      );
      this.notificationRunner.run(async (loop) => {
        await this.pgClient.listen(
          'jobs_finished',
          loop.wake.bind(loop),
          async () => {
            while (!loop.shuttingDown) {
              await this.drainNotifications(loop);
              await loop.sleep();
            }
          },
        );
      });
    }
    this.notifiers.set(id, n);
  }

  private async drainNotifications(loop: WorkLoop) {
    while (!loop.shuttingDown) {
      let waitingIds = [...this.notifiers.keys()];
      log.debug('jobs waiting for notification: %s', waitingIds);
      let result = (await this.query([
        `SELECT id, status, result FROM jobs WHERE status != 'unfulfilled' AND (`,
        ...any(waitingIds.map((id) => [`id=`, param(id)])),
        `)`,
      ] as Expression)) as Pick<JobsTable, 'id' | 'status' | 'result'>[];
      if (result.length === 0) {
        log.debug(`no jobs to notify`);
        return;
      }
      for (let row of result) {
        log.debug(
          `notifying caller that job %s finished with %s`,
          row.id,
          row.status,
        );
        // "!" because we only searched for rows matching our notifiers Map, and
        // we are the only code that deletes from that Map.
        let notifier = this.notifiers.get(row.id)!;
        this.notifiers.delete(row.id);
        if (row.status === 'resolved') {
          notifier.fulfill(row.result);
        } else {
          notifier.reject(row.result);
        }
      }
    }
  }

  get isDestroyed() {
    return this.#isDestroyed;
  }

  get hasStarted() {
    return this.#hasStarted;
  }

  async publish<T>(
    category: string,
    args: PgPrimitive,
    opts: QueueOpts = {},
  ): Promise<Job<T>> {
    let optsWithDefaults = Object.assign({}, defaultQueueOpts, opts);
    let queue = optsWithDefaults.queueName;
    {
      let rows = await this.query([
        'SELECT * FROM queues WHERE',
        ...every([
          ['queue_name =', param(queue)],
          ['category =', param(category)],
        ]),
      ] as Expression);
      if (rows.length === 0) {
        let { nameExpressions, valueExpressions } = asExpressions({
          queue_name: queue,
          category,
          status: 'idle',
        } as QueueTable);
        await this.query([
          'INSERT INTO queues',
          ...addExplicitParens(separatedByCommas(nameExpressions)),
          'VALUES',
          ...addExplicitParens(separatedByCommas(valueExpressions)),
        ] as Expression);
      }
    }
    {
      let { nameExpressions, valueExpressions } = asExpressions({
        args,
        queue,
        category,
      } as JobsTable);
      let [{ id: jobId }] = (await this.query([
        'INSERT INTO JOBS',
        ...addExplicitParens(separatedByCommas(nameExpressions)),
        'VALUES',
        ...addExplicitParens(separatedByCommas(valueExpressions)),
        'RETURNING id',
      ] as Expression)) as Pick<JobsTable, 'id'>[];
      log.debug(`%s created, notify jobs`, jobId);
      await this.query([`NOTIFY jobs`]);
      let notifier = new Deferred<T>();
      let job = new Job(jobId, notifier);
      this.addNotifier(jobId, notifier);
      return job;
    }
  }

  register<A, T>(category: string, handler: (arg: A) => Promise<T>) {
    this.handlers.set(category, handler);
  }

  async start() {
    if (!this.jobRunner && !this.#isDestroyed) {
      this.#hasStarted = true;
      await this.pgClient.startClient();
      this.jobRunner = new WorkLoop('jobRunner', this.pollInterval);
      this.jobRunner.run(async (loop) => {
        await this.pgClient.listen('jobs', loop.wake.bind(loop), async () => {
          while (!loop.shuttingDown) {
            await this.drainQueues(loop);
            await loop.sleep();
          }
        });
      });
    }
  }

  private async runJob(category: string, args: PgPrimitive) {
    let handler = this.handlers.get(category);
    if (!handler) {
      throw new Error(`unknown job handler ${category}`);
    }
    return await handler(args);
  }

  private async drainQueues(workLoop: WorkLoop) {
    await this.pgClient.withConnection(async ({ query }) => {
      while (!workLoop.shuttingDown) {
        log.debug(`draining queues`);
        await query(['BEGIN']);
        let jobs = (await query([
          // find the queue with the oldest job that isn't running and lock it.
          // SKIP LOCKED means we won't see any jobs that are already running.
          `SELECT * FROM jobs WHERE status='unfulfilled' ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED`,
        ])) as unknown as JobsTable[];
        if (jobs.length === 0) {
          log.debug(`found no work`);
          await query(['ROLLBACK']);
          return;
        }
        let firstJob = jobs[0];
        // when you have multiple queue clients, you also need to skip lock on
        // queue/categories that are also not idle as a job may have been
        // added immediately after the skip lock above runs (so it's not
        // locked) by a different queue client--we need to lock on a higher
        // order entity: the queue itself. Note that the previous hub v2
        // implementation locked all the jobs for the oldest unfulfilled job.
        // however, this resulted in a concurrency issue in that the
        // 'unfulfilled' status includes work not yet started as well as work
        // not yet completed. so if the oldest job is a job that happens to be
        // running, then we'll continue to look for work in that queue until
        // the running job has completed. this will starve other queues that
        // happen to have unstarted work that is newer than the job that is
        // currently running. This approach fixes that issue, and our tests
        // prove that.
        let idleQueues = (await query([
          'SELECT * FROM queues WHERE',
          ...every([
            ['queue_name =', param(firstJob.queue)],
            ['category =', param(firstJob.category)],
            ['status =', param('idle')],
          ]),
          'FOR UPDATE SKIP LOCKED',
        ] as Expression)) as unknown as QueueTable[];
        if (idleQueues.length === 0) {
          log.debug(
            `queue/category for job ${firstJob.id}, '${firstJob.queue}/${firstJob.category}' is not idle`,
          );
          await query(['ROLLBACK']);
          return;
        }
        await query([
          'UPDATE queues SET status =',
          param('working'),
          'WHERE',
          ...every([
            ['queue_name =', param(firstJob.queue)],
            ['category =', param(firstJob.category)],
          ]),
        ] as Expression);
        log.debug(
          `claimed queue %s which has %s unfulfilled jobs`,
          firstJob.queue,
          jobs.length,
        );
        let coalescedIds: number[] = jobs
          .filter(
            (r) =>
              r.category === firstJob.category &&
              isEqual(r.args, firstJob.args),
          )
          .map((r) => r.id);
        let newStatus: string;
        let result: PgPrimitive;
        try {
          log.debug(`running %s`, coalescedIds);
          result = await this.runJob(firstJob.category, firstJob.args);
          newStatus = 'resolved';
        } catch (err: any) {
          Sentry.captureException(err);
          console.error(
            `Error running job ${firstJob.id}: category=${
              firstJob.category
            } queue=${firstJob.queue} args=${JSON.stringify(firstJob.args)}`,
            err,
          );
          result = serializableError(err);
          newStatus = 'rejected';
        }
        log.debug(`finished %s as %s`, coalescedIds, newStatus);
        await query([
          `UPDATE jobs SET result=`,
          param(result),
          ', status=',
          param(newStatus),
          `, finished_at=now() WHERE `,
          ...any(coalescedIds.map((id) => [`id=`, param(id)])),
        ] as Expression);
        await query([
          'UPDATE queues SET status =',
          param('idle'),
          'WHERE',
          ...every([
            ['queue_name =', param(firstJob.queue)],
            ['category =', param(firstJob.category)],
          ]),
        ] as Expression);
        // NOTIFY takes effect when the transaction actually commits. If it
        // doesn't commit, no notification goes out.
        await query([`NOTIFY jobs_finished`]);
        await query(['COMMIT']);
        log.debug(`committed job completions, notified jobs_finished`);
      }
    });
  }

  async destroy() {
    this.#isDestroyed = true;
    if (this.jobRunner) {
      await this.jobRunner.shutDown();
    }
    if (this.notificationRunner) {
      await this.notificationRunner.shutDown();
    }
  }
}

function serializableError(err: any): Record<string, any> {
  try {
    let result = Object.create(null);
    for (let field of Object.getOwnPropertyNames(err)) {
      result[field] = err[field];
    }
    return result;
  } catch (megaError) {
    let stringish: string | undefined;
    try {
      stringish = String(err);
    } catch (_ignored) {
      // ignoring
    }
    return {
      failedToSerializeError: true,
      string: stringish,
    };
  }
}
