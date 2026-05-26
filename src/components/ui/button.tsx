import { cn } from "../../lib";

type ButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "default" | "ghost" | "outline";
};

export function Button({ className, variant = "default", ...props }: ButtonProps) {
  return (
    <button
      className={cn(
        "inline-flex h-9 items-center justify-center gap-2 rounded-md px-3 text-sm transition-colors",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-blue-500/20",
        variant === "default" && "bg-neutral-950 text-white hover:bg-neutral-800",
        variant === "ghost" && "text-neutral-600 hover:bg-neutral-100 hover:text-neutral-950",
        variant === "outline" && "border border-neutral-200 bg-white text-neutral-700 hover:bg-neutral-50",
        className
      )}
      {...props}
    />
  );
}
