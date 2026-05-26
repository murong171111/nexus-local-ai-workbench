import { cn } from "../../lib";

export function Input(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={cn(
        "h-10 w-full rounded-md border border-neutral-200 bg-white px-3 text-sm text-neutral-950",
        "placeholder:text-neutral-400 focus:border-blue-500/50 focus:outline-none focus:ring-2 focus:ring-blue-500/10",
        props.className
      )}
    />
  );
}
