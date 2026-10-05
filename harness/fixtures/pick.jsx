import { Title, Text, SimpleGrid, Card, Button, Slider, Group, Stack, Textarea } from '@mantine/core';
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
      <Group>
        <Button data-send>Send</Button>
      </Group>
    </Stack>
  );
}
