#!/bin/bash

lines=()
lines+=("🔍 Vibe Environment Sanity Check...")

# get local versions
vibe_deno=$(deno --version 2>/dev/null | awk 'NR==1 {print $2}')
vibe_elixir=$(elixir --version 2>/dev/null | grep Elixir | awk '{print $2}')

# get project versions from config / dockerfile if present
project_deno=$(grep -i 'deno' compose.yaml 2>/dev/null | \
  sed 's/.*deno://' | sed "s/[\"']//g" | head -n 1)
project_elixir=$(grep -i 'elixir' Dockerfile 2>/dev/null | \
  head -n 1 | sed 's/.*elixir//' | sed 's/[^0-9.]//g' | head -c 20)

lines+=("--------------------------------------------------------")
lines+=("Component         | Vibe Agent      | Project Stack   ")
lines+=("--------------------------------------------------------")
lines+=("Deno              | $(printf "%-15s" "$vibe_deno") | ${project_deno:-Not specified}      ")
lines+=("Elixir            | $(printf "%-15s" "$vibe_elixir") | ${project_elixir:-Not specified}    ")
lines+=("--------------------------------------------------------")

if [[ -n "$project_deno" && "$vibe_deno" != "$project_deno" ]]; then
    lines+=("⚠️  WARNING: Deno version mismatch detected!")
    lines+=("   Vibe is using $vibe_deno, but Project expects $project_deno.")
    lines+=("   Compiled artifacts in /dist may behave unexpectedly.")
fi

if [[ -n "$project_elixir" && "$vibe_elixir" != "$project_elixir" ]]; then
    lines+=("⚠️  WARNING: Elixir version mismatch detected!")
    lines+=("   Vibe is using $vibe_elixir, but Project expects $project_elixir.")
    lines+=("   BEAM files may be incompatible.")
fi

printf "%s\n" "${lines[@]}"
