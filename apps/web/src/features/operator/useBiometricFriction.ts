import { useState, useRef, useEffect, useCallback } from 'react';

export type StepStatus = 'locked' | 'ready' | 'pressing' | 'cooldown' | 'completed';

interface BiometricStep {
  id: string;
  status: StepStatus;
  pressProgress: number; // 0 a 100
  cooldownRemaining: number; // Segundos
}

const HOLD_TIME_MS = 3000;
const COOLDOWN_TIME_S = 15;

export const useBiometricFriction = () => {
  const [steps, setSteps] = useState<Record<string, BiometricStep>>({
    brakes: { id: 'brakes', status: 'ready', pressProgress: 0, cooldownRemaining: 0 },
    fluids: { id: 'fluids', status: 'locked', pressProgress: 0, cooldownRemaining: 0 },
    structural: { id: 'structural', status: 'locked', pressProgress: 0, cooldownRemaining: 0 },
  });

  const [isAllCompleted, setIsAllCompleted] = useState(false);
  const pressTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const cooldownTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Limpieza implacable al desmontar
  useEffect(() => {
    return () => {
      if (pressTimerRef.current) clearTimeout(pressTimerRef.current);
      if (cooldownTimerRef.current) clearInterval(cooldownTimerRef.current);
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, []);

  const unlockNext = useCallback((currentId: string) => {
    const sequence = ['brakes', 'fluids', 'structural'];
    const currentIndex = sequence.indexOf(currentId);
    
    if (currentIndex === sequence.length - 1) {
      setIsAllCompleted(true);
      return;
    }

    const nextId = sequence[currentIndex + 1];
    setSteps(prev => ({
      ...prev,
      [nextId]: { ...prev[nextId], status: 'ready' }
    }));
  }, []);

  const startCooldown = useCallback((stepId: string) => {
    setSteps(prev => ({
      ...prev,
      [stepId]: { ...prev[stepId], status: 'cooldown', cooldownRemaining: COOLDOWN_TIME_S, pressProgress: 100 }
    }));

    cooldownTimerRef.current = setInterval(() => {
      setSteps(prev => {
        const current = prev[stepId];
        if (current.cooldownRemaining <= 1) {
          clearInterval(cooldownTimerRef.current!);
          unlockNext(stepId);
          return { ...prev, [stepId]: { ...current, status: 'completed', cooldownRemaining: 0 } };
        }
        return { ...prev, [stepId]: { ...current, cooldownRemaining: current.cooldownRemaining - 1 } };
      });
    }, 1000);
  }, [unlockNext]);

  const handlePointerDown = useCallback((stepId: string) => {
    if (steps[stepId].status !== 'ready') return;

    setSteps(prev => ({ ...prev, [stepId]: { ...prev[stepId], status: 'pressing', pressProgress: 0 } }));

    // Simular el progreso visual (100% en 3 segundos)
    const startTime = Date.now();
    intervalRef.current = setInterval(() => {
      const elapsed = Date.now() - startTime;
      const progress = Math.min((elapsed / HOLD_TIME_MS) * 100, 100);
      setSteps(prev => ({ ...prev, [stepId]: { ...prev[stepId], pressProgress: progress } }));
    }, 100);

    pressTimerRef.current = setTimeout(() => {
      clearInterval(intervalRef.current!);
      startCooldown(stepId);
    }, HOLD_TIME_MS);
  }, [steps, startCooldown]);

  const handlePointerUp = useCallback((stepId: string) => {
    const step = steps[stepId];
    if (step.status === 'pressing') {
      // Abortar si levantó el dedo antes de los 3 segundos
      if (pressTimerRef.current) clearTimeout(pressTimerRef.current);
      if (intervalRef.current) clearInterval(intervalRef.current);
      
      setSteps(prev => ({ ...prev, [stepId]: { ...prev[stepId], status: 'ready', pressProgress: 0 } }));
    }
  }, [steps]);

  return { steps, isAllCompleted, handlePointerDown, handlePointerUp };
};
