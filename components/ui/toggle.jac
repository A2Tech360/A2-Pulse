import from "class-variance-authority" { cva }
import from "radix-ui" { Toggle as TogglePrimitive }
import from ...lib.utils { cn }

glob _toggleVariants: any = cva(
         "hover:text-foreground aria-pressed:bg-muted focus-visible:border-ring focus-visible:ring-ring/50 aria-invalid:ring-destructive/20 dark:aria-invalid:ring-destructive/40 aria-invalid:border-destructive data-[state=on]:bg-muted gap-1 rounded-none text-xs font-medium transition-all [&_svg:not([class*='size-'])]:size-4 group/toggle hover:bg-muted inline-flex items-center justify-center whitespace-nowrap outline-none focus-visible:ring-[3px] disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:shrink-0",
         {
             "variants": {
                 "variant": {
                     "default": "bg-transparent",
                     "outline": "border-input hover:bg-muted border bg-transparent"
                 },
                 "size": {
                     "default": "h-8 min-w-8 px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2",
                     "sm": "h-7 min-w-7 rounded-none px-2.5 has-data-[icon=inline-end]:pr-1.5 has-data-[icon=inline-start]:pl-1.5",
                     "lg": "h-9 min-w-9 px-2.5 has-data-[icon=inline-end]:pr-2 has-data-[icon=inline-start]:pl-2"
                 }
             },
             "defaultVariants": {"variant": "default", "size": "default"}
         }
     );

def:pub Toggle(props: any) -> JsxElement {
    variant = props["variant"] or "default";
    size = props["size"] or "default";
    variantsFn = _toggleVariants;
    computedClass = cn(
        variantsFn.call(
            None, {"variant": variant, "size": size, "className": props["className"]}
        )
    );
    return
        <TogglePrimitive.Root {**props} data-slot="toggle" className={computedClass}/>;
}

def:pub toggleVariants -> any {
    return _toggleVariants;
}
