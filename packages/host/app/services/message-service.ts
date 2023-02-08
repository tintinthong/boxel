import Service, { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import type CardService from '../services/card-service';
import { RealmPaths } from '@cardstack/runtime-common';

export default class MessageService extends Service {
  @service declare cardService: CardService;
  @tracked eventSource: EventSource | undefined = undefined;

  get isClosed() {
    return this.eventSource?.readyState === EventSource.CLOSED;
  }

  start() {
    if (!this.eventSource || this.isClosed) {
      let realmPath = new RealmPaths(this.cardService.defaultURL);
      this.eventSource = new EventSource(`${realmPath.url}_message`);
      console.log('Created new event source');
    }

    this.eventSource.onerror = (_ev: Event) => {
      if (this.eventSource?.readyState == EventSource.CONNECTING) {
        console.log(
          `Reconnecting (readyState=${this.eventSource.readyState})...`
        );
      } else if (this.isClosed) {
        console.log(
          `Connection closed (readyState=${this.eventSource?.readyState})`
        );
      } else {
        console.log(`An error has occured`);
      }
    };

    this.eventSource.onmessage = (e: MessageEvent) => {
      console.log('Event: message, data: ' + e.data);
    };
  }

  stop() {
    if (this.eventSource) {
      this.eventSource.close();
      if (this.isClosed) {
        console.log('Connection closed');
        this.eventSource = undefined;
      }
    }
  }
}
