import { Stack, TextInput, Textarea, NumberInput, Checkbox, Switch, Radio, Group, SegmentedControl, NativeSelect, Select, Slider, Rating, Chip, Button, Title } from '@mantine/core';
import { useRecord } from '@bridge';

export default function Page({ data }) {
  const [tone, setTone] = useRecord('tone', 'plain');
  const [size, setSize] = useRecord('size', 12);
  return (
    <Stack gap="sm">
      <Title order={1}>{data.title}</Title>
      <TextInput data-record="name" label="Name" defaultValue="" />
      <Textarea data-record="notes" label="Notes" />
      <NumberInput data-record="count" label="Count" defaultValue={3} />
      <Checkbox data-record="agree" label="Agree" />
      <Switch data-record="dark" label="Dark" />
      <Radio.Group data-record="side" label="Side">
        <Group><Radio value="left" label="Left" /><Radio value="right" label="Right" /></Group>
      </Radio.Group>
      <SegmentedControl data-record="view" data={['grid', 'list']} />
      <NativeSelect data-record="font" data={['Inter', 'Georgia']} />
      <Select data-record="tone-visual" data={['plain', 'warm']} value={tone} onChange={setTone} label="Tone" />
      <Slider value={size} onChange={setSize} min={8} max={24} w={200} />
      <Rating data-record="stars" />
      <Group data-record="tags">
        <Chip.Group multiple><Chip value="a">A</Chip><Chip value="b">B</Chip></Chip.Group>
      </Group>
      <Button data-send>Send</Button>
    </Stack>
  );
}
