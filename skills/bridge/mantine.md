# Mantine pages

A Mantine page is two files next to each other:

- `page.jsx`: the code. One default-exported component that renders its props.
- `page.data.json`: everything that changes between rewrites (prose, options,
  evidence, numbers). Rewriting it pushes new data into the running page with
  no reload. Rewriting the `.jsx` rebuilds and reloads.

`bridge page.jsx` builds it (about 50 ms) and opens it. A build error is
shown in the window as a build failure with the compiler's message; fix the
file and it builds again.

Put everything you might reword into the data file. Put a `title` in it; it
becomes the window title.

## Shape

`decision.jsx`:

```jsx
import { Title, Text, SimpleGrid, Card, Slider, Textarea, Button, Group, Stack } from '@mantine/core';
import { useRecord } from '@bridge';

export default function Page({ data }) {
  const [radius, setRadius] = useRecord('radius', 8);
  return (
    <Stack gap="md">
      <div>
        <Title order={1}>{data.title}</Title>
        <Text c="dimmed">{data.intro}</Text>
      </div>
      <Title order={2}>Layout</Title>
      <SimpleGrid cols={2}>
        {data.options.map((o) => (
          <Card key={o.value} withBorder data-record="layout" data-value={o.value}>
            <Text fw={600}>{o.label}</Text>
            <Text size="sm">{o.evidence}</Text>
          </Card>
        ))}
      </SimpleGrid>
      <Title order={2}>Corner radius</Title>
      <Slider value={radius} onChange={setRadius} min={0} max={24} w={240} />
      <Textarea data-record="note" placeholder="Optional" autosize minRows={2} />
      <Group><Button data-send>Send</Button></Group>
    </Stack>
  );
}
```

`decision.data.json`:

```json
{
  "title": "Card layout for the archive",
  "intro": "Two layouts survive the content; pick one.",
  "options": [
    { "value": "grid", "label": "Grid", "evidence": "Three columns at desktop." },
    { "value": "list", "label": "List", "evidence": "One entry per row." }
  ]
}
```

Available imports: `react`, `react-dom/client`, `@mantine/core`,
`@mantine/hooks`, and `@bridge` (`useRecord`, `record`, `send`). Nothing else
is installed; do not import other packages. JSX only, no TypeScript.

## Recording: the cheat sheet

Verified against the running app. Two mechanisms:

1. **`data-record` on the component** for anything that renders a real
   `<input>`, `<select>` or `<textarea>` (Mantine forwards the attribute to
   it) or a group of radios/checkboxes.
2. **`useRecord(key, initial)`** for anything whose value never reaches a DOM
   input. Returns `[value, setValue]`; `setValue` records.

This is the whole vocabulary. Every row is rendered by
`harness/fixtures/gallery.jsx` and checked on every harness run; a component
that is not in this table has not been verified, so do not reach for it.

| Component | Works with | Records |
| --- | --- | --- |
| `TextInput`, `Textarea`, `NumberInput` | `data-record` | string (NumberInput too: a string) |
| `Checkbox`, `Switch` | `data-record` | boolean |
| `Radio.Group` | `data-record` on the group | chosen value |
| `SegmentedControl` | `data-record` | chosen value |
| `NativeSelect` | `data-record` | chosen value |
| `Rating` | `data-record` | number as string ("4") |
| `Chip.Group` | `data-record` on a wrapping `<Group>`, not on `Chip.Group` (it renders no element) | array when `multiple`, else value |
| `Select` | `useRecord` (`value`/`onChange`) | the chosen value |
| `Slider` | `useRecord` | number |
| `Card`, any element as an option | `data-record` + `data-value` | chosen value; the chosen one gets `data-selected` |
| `Button` with `data-send` | | Send |

Layout and evidence, no recording: `Title`, `Text` (`c="dimmed"` for muted),
`Stack`, `Group`, `SimpleGrid`, `Card` (`withBorder`), `Table`
(`Table.Thead`/`Table.Tr`/`Table.Th`/`Table.Td`), `Badge`, `Code` (`block`),
`Divider`, `Image` (absolute path in `src`).

Use `defaultValue`, not `value`, on `data-record` inputs unless you also manage
their state: when the user reopens a page, Bridge puts their earlier answers
back into the inputs, and a controlled input would overwrite them. `useRecord` handles
this itself (it starts from their earlier answer if there is one).

## Two things that go wrong

- `useRecord('key', initial)` records only when the user changes it. If the
  initial value is itself an answer you need, read it as "not answered" and
  use your default.
- The offered `data-value`s are part of the page's questions. Changing the
  option list in `page.data.json` is a new version (the user is told, answers
  move to history). Changing labels or evidence is free.

## Look

The theme follows the system: `-apple-system`, 13px, system accent as the
primary colour, light and dark from the system appearance. Use Mantine's
components and props; do not set colours by hand.
