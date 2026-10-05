import { Title, Text, Stack, Group, SimpleGrid, Card, Button, Table, Badge, Code, Divider, Image, TextInput, Textarea, NumberInput, Checkbox, Switch, Radio, SegmentedControl, NativeSelect, Select, Slider, Rating, Chip } from '@mantine/core';
import { useRecord } from '@bridge';

export default function Page({ data }) {
  const [tone, setTone] = useRecord('tone', 'plain');
  const [size, setSize] = useRecord('size', 12);
  return (
    <Stack gap="md">
      <div>
        <Title order={1}>{data.title}</Title>
        <Text c="dimmed">Every component skills/bridge/mantine.md documents, rendered once.</Text>
      </div>
      <Title order={2}>Options</Title>
      <SimpleGrid cols={2}>
        {data.options.map((o) => (
          <Card key={o.value} withBorder data-record="layout" data-value={o.value}>
            <Group justify="space-between"><Text fw={600}>{o.label}</Text><Badge variant="light">{o.badge}</Badge></Group>
            <Text size="sm">{o.evidence}</Text>
          </Card>
        ))}
      </SimpleGrid>
      <Title order={2}>Evidence</Title>
      <Table>
        <Table.Thead><Table.Tr><Table.Th>Step</Table.Th><Table.Th>Files</Table.Th></Table.Tr></Table.Thead>
        <Table.Tbody><Table.Tr><Table.Td>Export</Table.Td><Table.Td>1 new</Table.Td></Table.Tr></Table.Tbody>
      </Table>
      <Code block>bridge --read page.jsx</Code>
      <Image src="/System/Library/Desktop Pictures/Solid Colors/Silver.png" h={60} w={120} radius="sm" />
      <Divider />
      <Title order={2}>Controls</Title>
      <TextInput data-record="name" label="Name" />
      <Textarea data-record="notes" label="Notes" />
      <NumberInput data-record="count" label="Count" defaultValue={3} />
      <Checkbox data-record="agree" label="Agree" />
      <Switch data-record="dark" label="Dark" />
      <Radio.Group data-record="side" label="Side"><Group><Radio value="left" label="Left" /><Radio value="right" label="Right" /></Group></Radio.Group>
      <SegmentedControl data-record="view" data={['grid', 'list']} />
      <NativeSelect data-record="font" data={['Inter', 'Georgia']} label="Font" />
      <Select data={['plain', 'warm']} value={tone} onChange={setTone} label="Tone" />
      <Slider value={size} onChange={setSize} min={8} max={24} w={240} />
      <Rating data-record="stars" />
      <Group data-record="tags"><Chip.Group multiple><Chip value="a">A</Chip><Chip value="b">B</Chip></Chip.Group></Group>
      <Group><Button data-send>Send</Button></Group>
    </Stack>
  );
}
