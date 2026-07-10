import { divIcon } from 'leaflet';

// Utilizaremos los colores y estilos de Tailwind directamente en el HTML del divIcon

const createIconSvg = (colorClass: string, iconType: string) => {
  const isExcavator = iconType === 'excavator';
  // SVG Crudo para inyectar en el mapa
  const svgPath = isExcavator 
    ? `<path d="M5 20h14v-2H5v2zM19 9h-4V7c0-1.1-.9-2-2-2h-3c-1.1 0-2 .9-2 2v2H4c-1.1 0-2 .9-2 2v5h20v-5c0-1.1-.9-2-2-2zm-9-2h3v2h-3V7z" fill="currentColor"/>` // Icono genérico de máquina
    : `<path d="M20 8h-3V4H3c-1.1 0-2 .9-2 2v11h2c0 1.66 1.34 3 3 3s3-1.34 3-3h6c0 1.66 1.34 3 3 3s3-1.34 3-3h2v-5l-3-4zM6 18.5c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zm13.5-9l1.96 2.5H17V9.5h2.5zm-1.5 9c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5z" fill="currentColor"/>`; // Camión

  return `
    <div class="flex items-center justify-center w-12 h-12 rounded-full border-4 shadow-xl bg-background border-outline-variant ${colorClass}">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
        ${svgPath}
      </svg>
    </div>
  `;
};

export const createAssetIcon = (category: string, status: string) => {
  let colorClass = 'text-on-surface-variant'; // Default / Inactivo
  
  if (status === 'in_site') colorClass = 'text-emerald-500 border-emerald-500/50';
  if (status === 'maintenance') colorClass = 'text-amber-500 border-amber-500/50';
  if (status === 'offline') colorClass = 'text-red-500 border-red-500/50';

  return divIcon({
    html: createIconSvg(colorClass, category),
    className: '', // Tailwind se encarga de todo en el HTML
    iconSize: [48, 48],
    iconAnchor: [24, 24] // Centrado exacto
  });
};
