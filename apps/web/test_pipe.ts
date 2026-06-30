import { z } from 'zod';

const schema = z.union([z.string(), z.number()])
  .transform(v => Number(v))
  .pipe(z.number().positive('Debe ser un peso mayor a 0'))
  .nullable();

type In = z.input<typeof schema>;
type Out = z.output<typeof schema>;
