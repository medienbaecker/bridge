#!/bin/bash
source "$(dirname "$0")/../lib.sh"

pair_with_b

page=$(fixture decision.html)
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
id=$(bridge --share "$page" | jq -r '.share')
there="$CASE_DIR/state-b/bridge-dev/shared/$id/page.html"
for i in $(seq 1 60); do [ -f "$there" ] && break; sleep 0.25; done
b --do select "$there" >/dev/null
for i in $(seq 1 60); do [ "$(b --state | jq -r '.ready')" = "true" ] && break; sleep 0.25; done

until_is() { for i in $(seq 1 50); do [ "$(eval "$1")" = "$2" ] && return; sleep 0.1; done; }
click() { "$1" --js "$2" "document.querySelector('[data-value=$3]').click(); return 1" >/dev/null; }
dots() { "$1" --js "$2" "@bridge return [...document.querySelectorAll('.bridge-pick')].map((d) => d.closest('[data-value]')?.dataset.value + ' ' + d.textContent).join(',')" | jq -r .; }

click bridge "$page" grid
until_is "b --read '$there' | jq -r '.people.thomas.layout'" grid
check_json "his pick reaches her Mac" "$(b --read "$there")" '.people.thomas.layout' "grid"
check_json "her own answers stay empty" "$(b --read "$there")" '.answers | length' "0"
until_is "dots b '$there'" "grid thomas"
check "her page marks his pick with his name" "$(dots b "$there")" "grid thomas"

click b "$there" list
until_is "bridge --read '$page' | jq -r '.people.yoshie.layout'" list
read=$(bridge --read "$page")
check_json "her pick reaches his Mac" "$read" '.people.yoshie.layout' "list"
check_json "his own answer is still his" "$read" '.answers.layout' "grid"
until_is "dots bridge '$page'" "list yoshie"
check "his page marks her pick" "$(dots bridge "$page")" "list yoshie"
bridge --shot "$CASE_DIR/shots/his-mac.png" >/dev/null
check "and her page still shows his" "$(dots b "$there")" "grid thomas"

b --do point >/dev/null
b --js "$there" "const el = document.querySelector('[data-value=list] strong'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + 10, clientY: r.top + 5})); return 1" >/dev/null
sleep 0.3
b --js "$there" "const t = document.querySelector('.bridge-thread textarea'); t.value = 'list feels long'; t.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true})); return 1" >/dev/null
until_is "bridge --pins '$page' | jq -r '.[0].text // empty'" "list feels long"
pins=$(bridge --pins "$page")
check_json "her note reaches his Mac" "$pins" '.[0].text' "list feels long"
check_json "saying it is hers" "$pins" '.[0].person' "yoshie"
note=$(echo "$pins" | jq -r '.[0].id')
bridge --reply "$page" "$note" "shortened it" >/dev/null
until_is "b --pins '$there' | jq -r '.[0].said[0].text // empty'" "shortened it"
check_json "his agent's reply reaches her" "$(b --pins "$there")" '.[0].said[0] | "\(.by) \(.person) \(.text)"' "agent thomas shortened it"

b --quit >/dev/null; sleep 0.5
bridge --js "$page" "const r = document.querySelector('[data-record=radius]'); r.value = 20; r.dispatchEvent(new Event('change', {bubbles: true})); return 1" >/dev/null
sleep 0.3
b --peers >/dev/null
for i in $(seq 1 3); do until_is "b --read '$there' | jq -r '.people.thomas.radius'" 20; done
check_json "a pick made while her Mac was off arrives when it is back" "$(b --read "$there")" '.people.thomas.radius' "20"
check_json "and her own pick survived" "$(b --read "$there")" '.answers.layout' "list"
finish
