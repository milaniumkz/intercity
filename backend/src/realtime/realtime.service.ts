import { Injectable } from '@nestjs/common';
import { Observable, Subject } from 'rxjs';

export type RealtimeEvent = {
    type: string;
    entity: 'order' | 'driver' | 'system';
    entityId?: string;
    at: string;
    payload?: Record<string, unknown>;
};

@Injectable()
export class RealtimeService {
    private readonly bus = new Subject<RealtimeEvent>();

    publish(event: RealtimeEvent) {
        this.bus.next(event);
    }

    stream(): Observable<RealtimeEvent> {
        return this.bus.asObservable();
    }
}

