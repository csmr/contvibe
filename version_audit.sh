#!/bin/bash

lines=()
lines+=("🔍 Vibe Environment Sanity Check...")

# get local versions
vibe_deno=$(deno --version 2>/dev/null | awk 'NR==1 {print $2}')
vibe_elixir=$(elixir --version 2>/dev/null | grep Elixir | awk '{print $2}')

# get project versions
project_deno=$(grep 'deno:' compose.yaml 2>/dev/null \
    | sed 's/.*deno://' | sed "s/[\"']//g" | head -n 1)
project_elixir=$(grep 'elixir' Dockerfile 2>/dev/null \
    | head -n 1 | sed 's/.*elixir//' | sed 's/[^0-9.]//g' | head -c 20)

lines+=("--------------------------------------------------------")
lines+=("Component         | Vibe Agent      | Project Stack   ")
lines+=("--------------------------------------------------------")
p_deno="${project_deno:-Not specified}"
p_elixir="${project_elixir:-Not specified}"
lines+=("Deno              | $(printf "%-15s" "$vibe_deno") | $p_deno")
lines+=("Elixir            | $(printf "%-15s" "$vibe_elixir") | $p_elixir")
lines+=("--------------------------------------------------------")

if [[ -n "$project_deno" && "$vibe_deno" != "$project_deno" ]]; then
    lines+=("⚠️  WARNING: Deno version mismatch detected!")
    lines+=("   Vibe ($vibe_deno) vs Project ($project_deno)")
    lines+=("   Compiled artifacts in /dist may behave unexpectedly.")
fi

if [[ -n "$project_elixir" && "$vibe_elixir" != "$project_elixir" ]]; then
    lines+=("⚠️  WARNING: Elixir version mismatch detected!")
    lines+=("   Vibe ($vibe_elixir) vs Project ($project_elixir)")
    lines+=("   BEAM files may be incompatible.")
fi

printf "%s\n" "${lines[@]}"
