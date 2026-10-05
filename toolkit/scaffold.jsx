import { StrictMode, useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { MantineProvider, createTheme } from '@mantine/core';
import Page from '@page';

const theme = createTheme({
  fontFamily: '-apple-system, system-ui, sans-serif',
  fontFamilyMonospace: 'ui-monospace, SF Mono, Menlo, monospace',
  fontSizes: { xs: '11px', sm: '12px', md: '13px', lg: '15px', xl: '20px' },
  headings: { fontFamily: '-apple-system, system-ui, sans-serif', sizes: { h1: { fontSize: '20px', fontWeight: '600' }, h2: { fontSize: '15px', fontWeight: '600' }, h3: { fontSize: '13px', fontWeight: '600' } } },
  defaultRadius: 'sm',
  radius: { xs: '4px', sm: '6px', md: '8px', lg: '10px', xl: '14px' },
  primaryShade: 6,
  cursorType: 'default',
});

function Root() {
  const [data, setData] = useState(window.__bridgeData);
  useEffect(() => {
    if (data && typeof data.title === 'string') document.title = data.title;
    document.dispatchEvent(new Event('bridge:rendered'));
  }, [data]);
  useEffect(() => {
    const onData = () => {
      try { setData(JSON.parse(document.documentElement.dataset.bridgeData)); } catch (e) { /* malformed: keep the last good data */ }
    };
    document.addEventListener('bridge:data', onData);
    return () => document.removeEventListener('bridge:data', onData);
  }, []);
  return (
    <MantineProvider theme={theme} defaultColorScheme="auto">
      <Page data={data} />
    </MantineProvider>
  );
}

createRoot(document.getElementById('root')).render(<StrictMode><Root /></StrictMode>);
