import { cn } from "../../lib";

export function Card({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "rounded-lg border border-neutral-200/80 bg-white shadow-[0_1px_2px_rgba(15,23,42,0.04)]",
        className
      )}
      {...props}
    />
  );
}
