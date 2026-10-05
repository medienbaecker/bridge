#!/bin/bash
# Verifies every claim the skill's Mantine cheat sheet makes about recording.
source "$(dirname "$0")/../lib.sh"
export BRIDGE_TOOLKIT="$ROOT/toolkit"

page=$(fixture controls.jsx)
fixture controls.data.json >/dev/null
repo
(cd "$CASE_DIR/pages" && bridge controls.jsx)
wait_ready
js() { bridge --js "$page" "$1"; }
fire() { js "const el = document.querySelector('$1'); $2; el.dispatchEvent(new Event('$3', {bubbles: true})); return 1" >/dev/null; }

fire "[data-record=name]" "el.value = 'Alex'" change
fire "[data-record=notes]" "el.value = 'ok'" change
fire "[data-record=count]" "el.value = '7'" change
js "document.querySelector('[data-record=agree]').click(); return 1" >/dev/null
js "document.querySelector('[data-record=dark]').click(); return 1" >/dev/null
js "document.querySelector('[data-record=side] input[value=right]').click(); return 1" >/dev/null
js "document.querySelector('[data-record=view] input[value=list]').click(); return 1" >/dev/null
fire "[data-record=font]" "el.value = 'Georgia'" change
js "document.querySelector('label[for=\"' + document.querySelector('[data-record=stars] input[value=\"4\"]').id + '\"]').click(); return 1" >/dev/null
js "document.querySelector('[data-record=tags] input[value=b]').click(); return 1" >/dev/null
js "document.documentElement.dataset.bridgeRecord = JSON.stringify({key: 'size', value: 16}); document.dispatchEvent(new Event('bridge:record')); return 1" >/dev/null
settle 0.4
read=$(bridge --read "$page")
check_json "TextInput" "$read" '.answers.name' "Alex"
check_json "Textarea" "$read" '.answers.notes' "ok"
check_json "NumberInput" "$read" '.answers.count' "7"
check_json "Checkbox is a boolean" "$read" '.answers.agree' "true"
check_json "Switch is a boolean" "$read" '.answers.dark' "true"
check_json "Radio.Group" "$read" '.answers.side' "right"
check_json "SegmentedControl" "$read" '.answers.view' "list"
check_json "NativeSelect" "$read" '.answers.font' "Georgia"
check_json "Rating" "$read" '.answers.stars' "4"
check_json "Chip.Group multiple is an array" "$read" '.answers.tags | join(",")' "b"
check_json "useRecord (Slider)" "$read" '.answers.size' "16"
check_json "useRecord initial value is not recorded until changed" "$read" '.answers.tone' "null"
snap controls "Every Mantine control the cheat sheet lists"
finish
