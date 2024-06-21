//@ts-expect-error no types for fastboot
import FastBoot from 'fastboot';
import { type FastBootInstance } from './fastboot-from-deployed';
import { instantiateFastBoot } from './fastboot-from-deployed';
import {
  type IndexRunner,
  type RunnerOpts,
} from '@cardstack/runtime-common/worker';
import { JSDOM } from 'jsdom';
import { type ErrorReporter } from '@cardstack/runtime-common/realm';
import { performance } from 'perf_hooks';

const appName = '@cardstack/host';
export async function makeFastBootIndexRunner(
  dist: URL | string,
  getRunnerOpts: (optsId: number) => RunnerOpts,
): Promise<{ getRunner: IndexRunner; distPath: string }> {
  let fastboot: FastBootInstance;
  let distPath: string;

  let globalWithErrorReporter = global as typeof globalThis & {
    __boxelErrorReporter: ErrorReporter;
  };

  if (typeof dist === 'string') {
    distPath = dist;
    fastboot = new FastBoot({
      distPath,
      resilient: false,
      buildSandboxGlobals(defaultGlobals: any) {
        return Object.assign({}, defaultGlobals, {
          __boxelErrorReporter: globalWithErrorReporter.__boxelErrorReporter,
          URL: globalThis.URL,
          Request: globalThis.Request,
          Response: globalThis.Response,
          btoa,
          performance,
          getRunnerOpts,
          _logDefinitions: (globalThis as any)._logDefinitions,
          jsdom: new JSDOM(''),
        });
      },
    }) as FastBootInstance;
  } else {
    ({ fastboot, distPath } = await instantiateFastBoot(
      appName,
      dist,
      (defaultGlobals: any) => {
        return Object.assign({}, defaultGlobals, {
          __boxelErrorReporter: globalWithErrorReporter.__boxelErrorReporter,
          URL: globalThis.URL,
          Request: globalThis.Request,
          Response: globalThis.Response,
          btoa,
          performance,
          getRunnerOpts,
          _logDefinitions: (globalThis as any)._logDefinitions,
          jsdom: new JSDOM(''),
        });
      },
    ));
  }
  return {
    getRunner: async (optsId: number) => {
      await fastboot.visit(`/indexer/${optsId}`, {
        // TODO we'll need to configure this host origin as part of the hosted realm work
        request: { headers: { host: 'localhost:4200' } },
      });
    },
    distPath,
  };
}

function btoa(str: string | Buffer) {
  let buffer;
  if (str instanceof Buffer) {
    buffer = str;
  } else {
    buffer = Buffer.from(str.toString(), 'binary');
  }
  return buffer.toString('base64');
}
