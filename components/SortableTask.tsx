"use client";

import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import type { ComponentProps } from "react";
import { TaskCard } from "./TaskCard";

export function SortableTask(props: ComponentProps<typeof TaskCard>) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: props.task.id });
  return (
    <div
      ref={setNodeRef}
      style={{ transform: CSS.Translate.toString(transform), transition }}
      className={`touch-manipulation outline-none focus-visible:rounded-xl focus-visible:ring-2 focus-visible:ring-amber-400 ${isDragging ? "opacity-30" : ""}`}
      {...attributes}
      {...listeners}
      aria-roledescription="draggable task"
      aria-label={`Drag “${props.task.title}”`}
    >
      <TaskCard {...props} />
    </div>
  );
}
