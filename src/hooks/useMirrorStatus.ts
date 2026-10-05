import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';

import { getStatus, type MirrorStatus } from '../native/screenMirror';

const POLL_INTERVAL_MS = 1000;

/**
 * Consulta o estado do espelhamento uma vez por segundo enquanto o app está em primeiro plano.
 * `refresh` força uma leitura imediata (ex.: logo após mudar uma configuração).
 */
export function useMirrorStatus(): {
  status: MirrorStatus | null;
  refresh: () => void;
} {
  const [status, setStatus] = useState<MirrorStatus | null>(null);
  const mounted = useRef(true);

  const refresh = useCallback(() => {
    getStatus()
      .then(next => {
        if (mounted.current) {
          setStatus(next);
        }
      })
      .catch(() => {});
  }, []);

  useEffect(() => {
    mounted.current = true;
    let timer: ReturnType<typeof setInterval> | undefined;

    const startPolling = () => {
      if (timer === undefined) {
        refresh();
        timer = setInterval(refresh, POLL_INTERVAL_MS);
      }
    };
    const stopPolling = () => {
      if (timer !== undefined) {
        clearInterval(timer);
        timer = undefined;
      }
    };

    if (AppState.currentState !== 'background') {
      startPolling();
    }
    const subscription = AppState.addEventListener('change', state => {
      if (state === 'active') {
        startPolling();
      } else if (state === 'background') {
        stopPolling();
      }
    });

    return () => {
      mounted.current = false;
      stopPolling();
      subscription.remove();
    };
  }, [refresh]);

  return { status, refresh };
}
