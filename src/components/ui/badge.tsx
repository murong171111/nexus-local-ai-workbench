import { cn } from "../../lib";

type BadgeProps = {
  children: React.ReactNode;
  tone?: "default" | "blue" | "green" | "amber" | "red" | "muted";
  className?: string;
};

const tones = {
  default: "border-neutral-200 bg-neutral-50 text-neutral-700",
  blue: "border-blue-200 bg-blue-50 text-blue-700",
  green: "border-emerald-200 bg-emerald-50 text-emerald-700",
  amber: "border-amber-200 bg-amber-50 text-amber-700",
  red: "border-red-200 bg-red-50 text-red-700",
  muted: "border-neutral-200 bg-white text-neutral-500"
};

export function Badge({ children, tone = "default", className }: BadgeProps) {
  return (
    <span
      className={cn(
        "inline-flex h-6 items-center gap-1 rounded-md border px-2 font-mono text-[11px] leading-none shadow-none",
        tones[tone],
        className
      )}
    >
      {children}
    </span>
  );
}
