import from "radix-ui" { ToggleGroup as ToggleGroupPrimitive }
import from ...lib.utils { cn }
import from ".toggle" { toggleVariants }

def:pub ToggleGroup(props: any) -> JsxElement {
    variant = props["variant"] or "default";
    size = props["size"] or "default";
    spacing = props["spacing"] or 0;
    orientation = props["orientation"] or "horizontal";

    return
        <ToggleGroupPrimitive.Root
            {**props}
            data-slot="toggle-group"
            data-variant={variant}
            data-size={size}
            data-spacing={spacing}
            data-orientation={orientation}
            className={cn(
                "rounded-lg data-[size=sm]:rounded-[min(var(--radius-md),10px)] group/toggle-group flex w-fit flex-row items-center data-vertical:flex-col data-vertical:items-stretch",
                props["className"]
            )}
        >
            {props["children"]}
        </ToggleGroupPrimitive.Root>;
}

def:pub ToggleGroupItem(props: any) -> JsxElement {
    variant = props["variant"] or "default";
    size = props["size"] or "default";
    variantsFn: any = toggleVariants();
    computedClass = cn(
        "group-data-[spacing=0]/toggle-group:rounded-none group-data-[spacing=0]/toggle-group:px-2 group-data-[spacing=0]/toggle-group:has-data-[icon=inline-end]:pr-1.5 group-data-[spacing=0]/toggle-group:has-data-[icon=inline-start]:pl-1.5 group-data-horizontal/toggle-group:data-[spacing=0]:first:rounded-l-lg group-data-vertical/toggle-group:data-[spacing=0]:first:rounded-t-lg group-data-horizontal/toggle-group:data-[spacing=0]:last:rounded-r-lg group-data-vertical/toggle-group:data-[spacing=0]:last:rounded-b-lg shrink-0 focus:z-10 focus-visible:z-10",
        variantsFn.call(None, {"variant": variant, "size": size}),
        props["className"]
    );
    return
        <ToggleGroupPrimitive.Item
            {**props}
            data-slot="toggle-group-item"
            data-variant={variant}
            data-size={size}
            className={computedClass}
        >
            {props["children"]}
        </ToggleGroupPrimitive.Item>;
}
