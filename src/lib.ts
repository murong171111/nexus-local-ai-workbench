import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function fileUrl(path: string) {
  return `file://${path}`;
}

export function riskTone(count: number) {
  if (count >= 4) return "high";
  if (count >= 2) return "medium";
  if (count === 1) return "low";
  return "none";
}
